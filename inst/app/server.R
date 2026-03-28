# server.R

library(shiny)
library(shinybusy)
library(XML)
library(plyr)
library(dplyr)
library(DT)
library(yaml)
library(processx)
library(digest)
library(htmltools)
library(htmlwidgets)
library(shinyFiles)

app_root <- normalizePath(".", winslash = "/", mustWork = TRUE)

# Source helpers (paths are relative to the app directory)
source("R/00_utils.R")
source("R/01_metadata.R")
source("R/02_user_db_registry.R")
source("R/03_alignment_rendering.R")
source("R/04_blast_xml.R")
source("R/05_makeblastdb.R")
source("R/06_diamond_xml.R")
source("R/07_aligner_dispatch.R")
source("R/90_diagnostics.R", local = TRUE)

server <- function(input, output, session) {
  session$onSessionEnded(function() stopApp())
  
  # ------- Helper to get paths -------
  app_path <- function(...) {
    file.path(getwd(), ...)
  }
  
  wire_diagnostics(output)
  
  output$run_panel_title <- renderUI({
    aligner <- toupper(input$aligner %||% "BLAST")
    if (identical(aligner, "DIAMOND")) "Run DIAMOND" else "Run BLAST"
  })
  
  output$run_action_button <- renderUI({
    aligner <- toupper(input$aligner %||% "BLAST")
    lbl <- if (identical(aligner, "DIAMOND")) "run DIAMOND" else "run BLAST"
    actionButton("blast", lbl)
  })
  
  # ---------- Metadata load ----------
  subject_meta <- load_subject_meta(
    tsv_path = "metadata/subject_meta.tsv",
    csv_path = "metadata/subject_meta.csv"
  )
  
  # ---------- Config + registry ----------
  cfg <- load_or_default_config("config.yml")
  log_registry_config(cfg, cfg_file = "config.yml")
  
  seed <- build_seed_registry(cfg)
  user_df0 <- load_user_dbs()
  log_user_db_file(user_db_file, user_df0)
  
  reg0 <- merge_seed_and_user_registry(seed, user_df0)
  log_registry_entries(reg0)
  
  db_registry <- reactiveVal(reg0)
  
  # Allowed choices per program (aligner-aware, backward compatible)
  allowed_db_choices <- function(program, aligner = NULL) {
    reg <- db_registry()
    aligner <- toupper((aligner %||% "BLAST"))
    
    if (identical(aligner, "DIAMOND")) {
      # DIAMOND: only local .dmnd databases (by registry path)
      return(reg$name[grepl("\\.dmnd$", reg$path, ignore.case = TRUE)])
    }
    
    # BLAST: existing behavior
    allowed_db_choices_for_program(reg, program)
  }
  
  # Keep program choices synchronized with selected aligner
  observeEvent(input$aligner, {
    aligner <- toupper(input$aligner %||% "BLAST")
    choices <- aligner_program_choices(aligner)
    
    selected <- input$program
    if (is.null(selected) || !(selected %in% choices)) {
      selected <- choices[1]
    }
    
    updateSelectInput(session, "program", choices = choices, selected = selected)
  }, ignoreInit = FALSE)
  
  # Dynamic DB choices
  observeEvent(list(input$program, input$aligner), {
    aligner <- toupper(input$aligner %||% "BLAST")
    choices <- unique(allowed_db_choices(input$program, aligner))
    
    if (!length(choices)) {
      if (identical(aligner, "DIAMOND")) {
        # No DIAMOND DBs registered: show empty to force registration/selection
        updateSelectInput(session, "db", choices = character(0), selected = character(0))
        return(invisible(NULL))
      }
      choices <- if (input$program %in% c("blastn", "tblastn")) "nt" else "nr"
    }
    
    sel <- input$db
    if (is.null(sel) || !(sel %in% choices)) sel <- choices[1]
    updateSelectInput(session, "db", choices = choices, selected = sel)
  }, ignoreInit = FALSE)
  
  # Cache for alignment XML
  .cache <- new.env(parent = emptyenv())
  
  # Current XML (from a fresh run or a loaded file)
  xml_current <- reactiveVal(NULL)
  
  # Use uploaded FASTA?
  use_upload <- reactive({
    is.list(input$fasta) &&
      !is.null(input$fasta$datapath) &&
      nzchar(input$fasta$datapath) &&
      file.exists(input$fasta$datapath)
  })
  
  # ---------- shinyFiles directory picker wiring ----------
  volumes <- build_shinyfiles_volumes()
  shinyFiles::shinyDirChoose(
    input, "make_outdir_browse",
    roots = volumes, session = session, allowDirCreate = TRUE
  )
  
  output$make_outdir_selected <- renderText({
    input$make_outdir
  })
  
  observeEvent(input$make_outdir_browse, {
    sel <- shinyFiles::parseDirPath(volumes, input$make_outdir_browse)
    if (length(sel) == 1 && nzchar(sel)) {
      path <- normalizePath(sel, winslash = "/", mustWork = FALSE)
      updateTextInput(session, "make_outdir", value = path)
    }
  })
  
  # ---- Run alignment (BLAST or DIAMOND) ----
  blastresults <- eventReactive(input$blast, {
    aligner <- toupper(input$aligner %||% "BLAST")
    spinner_txt <- if (identical(aligner, "DIAMOND")) "Running DIAMOND..." else "Running BLAST..."
    shinybusy::show_modal_spinner(spin = "fading-circle", text = spinner_txt)
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    validate_alignment_inputs(input, use_upload = use_upload())
    
    prog <- match.arg(input$program, aligner_program_choices(aligner))
    
    # Resolve DB selection
    if (identical(aligner, "DIAMOND")) {
      reg <- db_registry()
      row <- reg[match(input$db, reg$name), , drop = FALSE]
      
      shiny::validate(
        shiny::need(nrow(row) == 1 && nzchar(row$path), paste("Unknown DB:", input$db)),
        shiny::need(grepl("\\.dmnd$", row$path, ignore.case = TRUE), "DIAMOND requires a .dmnd database.")
      )
      
      db_res <- list(db_path = row$path, remote = FALSE)
    } else {
      db_res <- resolve_db_selection(
        db_input = input$db,
        registry = db_registry(),
        program  = prog
      )
    }
    
    # Cache key depends on aligner too
    file_sig <- make_query_signature(input, use_upload = use_upload())
    key <- digest::digest(list(aligner, prog, input$db, input$eval, file_sig))
    
    if (exists(key, envir = .cache)) {
      xml <- get(key, envir = .cache)
      xml_current(xml)
      return(xml)
    }
    
    tmp_fa <- materialize_query_fasta(input, use_upload = use_upload())
    on.exit(tmp_fa$cleanup(), add = TRUE)
    
    xml <- run_aligner_as_xml(
      aligner     = aligner,
      program     = prog,
      query_fasta = tmp_fa$path,
      db          = db_res$db_path,
      evalue      = input$eval,
      remote      = db_res$remote
    )
    
    assign(key, xml, envir = .cache)
    xml_current(xml)
    xml
  }, ignoreNULL = TRUE)
  
  observeEvent(input$blast, {
    invisible(blastresults())
  })
  
  # ---- Load BLAST XML from file ----
  observeEvent(input$blast_xml, {
    req(is.list(input$blast_xml), nzchar(input$blast_xml$datapath), file.exists(input$blast_xml$datapath))
    xml <- XML::xmlParse(input$blast_xml$datapath, useInternalNodes = TRUE)
    xml_current(xml)
  })
  
  # ---- Parse alignment XML (table data) ----
  parsedresults <- reactive({
    x <- xml_current()
    req(!is.null(x))
    
    aligner <- toupper(input$aligner %||% "BLAST")
    out <- parse_aligner_xml_to_df(x, aligner = aligner)
    logf("[ALIGNMENT][%s] Parsed %d rows", aligner, nrow(out))
    out
  })
  
  # ---- Results table ----
  output$alignmentResults <- renderDT({
    df <- parsedresults()
    render_alignment_results_dt(df = df, subject_meta = subject_meta)
  })
  
  # ---- Clicked row summary ----
  output$clicked <- renderTable({
    sel <- input$alignmentResults_rows_selected
    req(length(sel) == 1)
    
    df <- parsedresults()
    row <- df[sel, , drop = FALSE]
    
    render_clicked_summary_table(row = row, subject_meta = subject_meta)
  },
  rownames = FALSE, colnames = FALSE,
  sanitize.text.function = function(x) x)
  
  # ---- Alignment text (with coordinates) ----
  output$alignment <- renderText({
    sel <- input$alignmentResults_rows_selected
    req(length(sel) == 1)
    
    x <- xml_current()
    req(!is.null(x))
    
    render_alignment_for_row(xml_doc = x, row_index = sel, width = 40)
  })
  
  # ---- Report download (uses current XML) ----
  output$download_report <- downloadHandler(
    filename = function() paste0("align_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html"),
    content = function(file) {
      x <- isolate(xml_current())
      validate(need(!is.null(x), "Load or run alignment first."))
      
      df <- isolate(parsedresults())
      validate(need(nrow(df) > 0, "No results to export."))
      
      build_and_save_html_report(
        file         = file,
        xml_doc      = x,
        df           = df,
        subject_meta = subject_meta
      )
    }
  )
  
  # ---- Download raw BLAST XML ----
  output$download_xml <- downloadHandler(
    filename = function() paste0("align_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xml"),
    content = function(file) {
      doc <- isolate(xml_current())
      validate(need(!is.null(doc), "No alignment XML available"))
      saveXML(doc, file = file)
    }
  )
  
  # ---- Build local BLAST DB ----
  make_log <- reactiveVal("")
  append_make_log <- function(...) {
    msg <- sprintf(...)
    old <- make_log()
    make_log(paste0(old, if (nzchar(old)) "\n" else "", msg))
  }
  
  output$make_log <- renderText(make_log())
  
  observeEvent(input$make_run, {
    run_makeblastdb_and_register(
      input          = input,
      cfg            = cfg,
      db_registry    = db_registry,
      allowed_db_fun = function(program) allowed_db_choices(program, aligner = "BLAST"),
      session        = session,
      append_log     = append_make_log
    )
  })
}