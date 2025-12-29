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

# Source helpers (paths are relative to the app directory)
source("R/00_utils.R")
source("R/01_metadata.R")
source("R/02_user_db_registry.R")
source("R/03_alignment_rendering.R")
source("R/04_blast_xml.R")
source("R/05_makeblastdb.R")

server <- function(input, output, session) {
  session$onSessionEnded(function() stopApp())
  
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
  
  # Allowed choices per program
  allowed_db_choices <- function(program) {
    reg <- db_registry()
    allowed_db_choices_for_program(reg, program)
  }
  
  # Dynamic DB choices
  observeEvent(input$program, {
    choices <- unique(allowed_db_choices(input$program))
    if (!length(choices)) {
      choices <- if (input$program %in% c("blastn", "tblastn")) "nt" else "nr"
    }
    updateSelectInput(session, "db", choices = choices, selected = choices[1])
  }, ignoreInit = FALSE)
  
  # Cache for BLAST XML
  .cache <- new.env(parent = emptyenv())
  
  # Current XML (from a fresh run or a loaded file)
  xml_current <- reactiveVal(NULL)
  
  # Use uploaded FASTA?
  use_upload <- reactive({
    is.list(input$fasta) && !is.null(input$fasta$datapath) &&
      nzchar(input$fasta$datapath) && file.exists(input$fasta$datapath)
  })
  
  # ---------- shinyFiles directory picker wiring ----------
  volumes <- build_shinyfiles_volumes()
  shinyFiles::shinyDirChoose(
    input, "make_outdir_browse",
    roots = volumes, session = session, allowDirCreate = TRUE
  )
  
  output$make_outdir_selected <- renderText({ input$make_outdir })
  
  observeEvent(input$make_outdir_browse, {
    sel <- shinyFiles::parseDirPath(volumes, input$make_outdir_browse)
    if (length(sel) == 1 && nzchar(sel)) {
      path <- normalizePath(sel, winslash = "/", mustWork = FALSE)
      updateTextInput(session, "make_outdir", value = path)
    }
  })
  
  # ---- Run BLAST ----
  blastresults <- eventReactive(input$blast, {
    shinybusy::show_modal_spinner(spin = "fading-circle", text = "Running BLAST...")
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    validate_blast_inputs(input, use_upload = use_upload())
    
    prog <- match.arg(input$program, c("blastn", "tblastn", "blastp", "blastx"))
    
    db_res <- resolve_db_selection(
      db_input   = input$db,
      registry   = db_registry(),
      program    = prog
    )
    
    # Cache key depends on program, db choice, evalue, and query payload signature
    file_sig <- make_query_signature(input, use_upload = use_upload())
    key <- digest::digest(list(prog, input$db, input$eval, file_sig))
    
    # Return cached XML if present
    if (exists(key, envir = .cache)) {
      xml <- get(key, envir = .cache)
      xml_current(xml)
      return(xml)
    }
    
    # Ensure we have a FASTA file (temporary if needed)
    tmp_fa <- materialize_query_fasta(input, use_upload = use_upload())
    on.exit(tmp_fa$cleanup(), add = TRUE)
    
    # Run BLAST and parse XML
    xml <- run_blast_as_xml(
      prog   = prog,
      query  = tmp_fa$path,
      db     = db_res$db_path,
      eval   = input$eval,
      remote = db_res$remote
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
  
  # ---- Parse BLAST XML (table data) ----
  parsedresults <- reactive({
    x <- xml_current()
    req(!is.null(x))
    out <- parse_blast_xml_to_df(x)
    logf("[BLAST] Parsed %d rows", nrow(out))
    out
  })
  
  # ---- Results table ----
  output$blastResults <- renderDT({
    df <- parsedresults()
    render_blast_results_dt(df = df, subject_meta = subject_meta)
  })
  
  # ---- Clicked row summary ----
  output$clicked <- renderTable({
    sel <- input$blastResults_rows_selected
    req(length(sel) == 1)
    
    df  <- parsedresults()
    row <- df[sel, , drop = FALSE]
    
    render_clicked_summary_table(row = row, subject_meta = subject_meta)
  },
  rownames = FALSE, colnames = FALSE,
  sanitize.text.function = function(x) x)
  
  # ---- Alignment text (with coordinates) ----
  output$alignment <- renderText({
    sel <- input$blastResults_rows_selected
    req(length(sel) == 1)
    
    x <- xml_current()
    req(!is.null(x))
    
    render_alignment_for_row(xml_doc = x, row_index = sel, width = 40)
  })
  
  # ---- Report download (uses current XML) ----
  output$download_report <- downloadHandler(
    filename = function() paste0("blast_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html"),
    content = function(file) {
      x  <- isolate(xml_current()); validate(need(!is.null(x), "Load or run BLAST first."))
      df <- isolate(parsedresults()); validate(need(nrow(df) > 0, "No results to export."))
      
      build_and_save_html_report(
        file        = file,
        xml_doc      = x,
        df           = df,
        subject_meta = subject_meta
      )
    }
  )
  
  # ---- Download raw BLAST XML ----
  output$download_xml <- downloadHandler(
    filename = function() paste0("blast_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xml"),
    content  = function(file) {
      doc <- isolate(xml_current()); validate(need(!is.null(doc), "No BLAST XML available"))
      XML::saveXML(doc, file = file)
    }
  )
  
  # -------- makeblastdb integration with persistence --------
  make_log <- reactiveVal("")
  append_make_log <- function(...) make_log(paste0(make_log(), sprintf(...), "\n"))
  output$make_log <- renderText(make_log())
  
  observeEvent(input$make_run, {
    shinybusy::show_modal_spinner(spin = "fading-circle", text = "Building database...")
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    run_makeblastdb_and_register(
      input          = input,
      cfg            = cfg,
      db_registry    = db_registry,
      allowed_db_fun = allowed_db_choices,
      session        = session,
      append_log     = append_make_log
    )
  })
}

server