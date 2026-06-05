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
source("R/05_diamond_xml.R")
source("R/06_makeseqdb.R")
source("R/07_aligner_dispatch.R")
source("R/08_aligner_params.R")
source("R/09_search_strategy.R")
source("R/90_diagnostics.R", local = TRUE)

server <- function(input, output, session) {
  session$onSessionEnded(function() stopApp())
  
  app_path <- function(...) {
    file.path(getwd(), ...)
  }
  
  wire_diagnostics(output)
  
  output$run_panel_title <- renderUI({
    "Run alignment"
  })
  
  output$run_action_button <- renderUI({
    aligner <- toupper(input$aligner %||% "BLAST")
    lbl <- if (identical(aligner, "DIAMOND")) "Run DIAMOND" else "Run BLAST"
    actionButton("blast", lbl)
  })
  
  output$aligner_param_controls <- renderUI({
    aligner <- toupper(input$aligner %||% "BLAST")
    program <- input$program %||% NULL
    
    render_aligner_parameter_inputs(
      aligner = aligner,
      program = program,
      show_advanced = isTRUE(input$show_advanced_params)
    )
  })
  
  output$aligner_preset_control <- renderUI({
    aligner <- toupper(input$aligner %||% "BLAST")
    selectInput(
      "aligner_preset",
      "Preset",
      choices = preset_choices(aligner),
      selected = "Default"
    )
  })
  
  observeEvent(
    list(
      input$aligner,
      input$aligner_preset
    ),
    {
      
      req(input$aligner_preset)
      
      aligner <- toupper(input$aligner)
      
      preset <- get_preset_values(
        aligner,
        input$aligner_preset
      )
      
      defs <- get_aligner_parameter_defs(
        aligner,
        input$program
      )
      
      for (nm in names(preset)) {
        
        if (!nm %in% names(defs)) {
          next
        }
        
        id <- aligner_param_input_id(nm)
        
        def <- defs[[nm]]
        
        if (def$input == "numeric") {
          
          updateNumericInput(
            session,
            id,
            value = preset[[nm]]
          )
          
        } else if (def$input %in%
                   c(
                     "numeric_optional",
                     "numeric_decimal"
                   )) {
          
          updateTextInput(
            session,
            id,
            value = as.character(
              preset[[nm]]
            )
          )
          
        } else if (def$input == "select") {
          
          updateSelectInput(
            session,
            id,
            selected = preset[[nm]]
          )
        }
      }
    },
    ignoreInit = TRUE
  )
  
  # ---------- Metadata load ----------
  metadata_cache <- new.env(parent = emptyenv())
  
  subject_meta <- reactive({
    req(input$db)
    
    cache_key <- metadata_cache_key(input$db, db_registry())
    
    if (exists(cache_key, envir = metadata_cache, inherits = FALSE)) {
      logf("[META] Using cached metadata for DB: %s", input$db)
      return(get(cache_key, envir = metadata_cache, inherits = FALSE))
    }
    
    meta <- load_subject_meta_for_db(input$db, db_registry())
    assign(cache_key, meta, envir = metadata_cache)
    
    meta
  })
  
  # ---------- Config + registry ----------
  cfg <- load_or_default_config("config.yml")
  log_registry_config(cfg, cfg_file = "config.yml")
  
  seed <- build_seed_registry(cfg)
  user_df0 <- load_user_dbs()
  log_user_db_file(user_db_file, user_df0)
  
  reg0 <- merge_seed_and_user_registry(seed, user_df0)
  log_registry_entries(reg0)
  
  db_registry <- reactiveVal(reg0)
  
  pending_strategy <- reactiveVal(NULL)
  
  allowed_db_choices <- function(program, aligner = NULL) {
    reg <- db_registry()
    aligner <- toupper(aligner %||% "BLAST")
    allowed_db_choices_for_program(reg, program, aligner)
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
  
  # Keep database choices synchronized with selected program + aligner
  observeEvent(list(input$program, input$aligner), {
    req(input$program)
    
    aligner <- toupper(input$aligner %||% "BLAST")
    choices <- unique(allowed_db_choices(input$program, aligner))
    
    if (!length(choices)) {
      if (identical(aligner, "DIAMOND")) {
        # No DIAMOND databases registered yet
        updateSelectInput(session, "db", choices = character(0), selected = character(0))
        return(invisible(NULL))
      }
      
      # BLAST fallback for remote databases
      choices <- if (input$program %in% c("blastn", "tblastn", "tblastx")) "nt" else "nr"
    }
    
    selected <- input$db
    if (is.null(selected) || !(selected %in% choices)) {
      selected <- choices[1]
    }
    
    updateSelectInput(session, "db", choices = choices, selected = selected)
  }, ignoreInit = FALSE)
  
  # Cache for alignment XML
  .cache <- new.env(parent = emptyenv())
  
  # Current XML (from a fresh run or a loaded file)
  xml_current <- reactiveVal(NULL)
  
  use_upload <- reactive({
    is.list(input$fasta) &&
      !is.null(input$fasta$datapath) &&
      nzchar(input$fasta$datapath) &&
      file.exists(input$fasta$datapath)
  })
  
  # ---- Keep DB builder backend compatible with molecule type ----
  observeEvent(input$make_type, {
    req(input$make_type)
    
    if (identical(input$make_type, "nucl")) {
      updateSelectInput(
        session,
        "make_backend",
        choices = c("BLAST" = "blast"),
        selected = "blast"
      )
    } else {
      selected <- input$make_backend
      valid_choices <- c("BLAST" = "blast", "DIAMOND" = "diamond")
      
      if (is.null(selected) || !(selected %in% unname(valid_choices))) {
        selected <- "blast"
      }
      
      updateSelectInput(
        session,
        "make_backend",
        choices = valid_choices,
        selected = selected
      )
    }
  }, ignoreInit = FALSE)
  
  # ---- Keep DB builder backend compatible with molecule type ----
  observeEvent(input$make_type, {
    req(input$make_type)
    
    if (identical(input$make_type, "nucl")) {
      updateSelectInput(
        session,
        "make_backend",
        choices = c("BLAST" = "blast"),
        selected = "blast"
      )
    } else {
      selected <- input$make_backend
      valid_choices <- c("BLAST" = "blast", "DIAMOND" = "diamond")
      
      if (is.null(selected) || !(selected %in% unname(valid_choices))) {
        selected <- "blast"
      }
      
      updateSelectInput(
        session,
        "make_backend",
        choices = valid_choices,
        selected = selected
      )
    }
  }, ignoreInit = FALSE)
  
  # ---- Run alignment (BLAST or DIAMOND) ----
  blastresults <- eventReactive(input$blast, {
    aligner <- toupper(input$aligner %||% "BLAST")
    spinner_txt <- if (identical(aligner, "DIAMOND")) "Running DIAMOND..." else "Running BLAST..."
    shinybusy::show_modal_spinner(spin = "fading-circle", text = spinner_txt)
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    validate_alignment_inputs(input, use_upload = use_upload())
    
    prog <- match.arg(input$program, aligner_program_choices(aligner))
    
    evalue <- suppressWarnings(as.numeric(trimws(input$eval %||% "")))
    
    shiny::validate(
      shiny::need(
        is.finite(evalue) && evalue > 0,
        "Please provide a valid positive e-value, e.g. 1e-5, 0.001, or 1."
      )
    )
    
    params <- collect_aligner_params(
      input = input,
      aligner = aligner,
      program = prog
    )
    
    db_res <- resolve_db_selection(
      db_input = input$db,
      registry = db_registry(),
      program  = prog,
      aligner  = aligner
    )
    
    logf("[RUN] aligner=%s program=%s db=%s evalue=%s", aligner, prog, input$db, evalue)
    
    file_sig <- make_query_signature(input, use_upload = use_upload())
    key <- digest::digest(list(aligner, prog, input$db, evalue, file_sig, params))
    
    if (exists(key, envir = .cache, inherits = FALSE)) {
      xml <- get(key, envir = .cache, inherits = FALSE)
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
      evalue      = evalue,
      remote      = db_res$remote,
      params      = params
    )
    
    logf("[RUN] XML returned for aligner=%s program=%s", aligner, prog)
    
    assign(key, xml, envir = .cache)
    xml_current(xml)
    xml
  }, ignoreNULL = TRUE)
  
  observeEvent(input$blast, {
    invisible(blastresults())
  })
  
  # ---- Load search strategy from file
  
  observeEvent(
    list(input$aligner, input$aligner_preset),
    {
      strategy <- pending_strategy()
      req(!is.null(strategy))
      
      aligner <- toupper(strategy$aligner %||% "BLAST")
      
      req(identical(toupper(input$aligner %||% ""), aligner))
      
      preset <- strategy$preset %||% ""
      valid_presets <- preset_choices(aligner)
      
      if (nzchar(preset) && preset %in% valid_presets) {
        updateSelectInput(session, "aligner_preset", selected = preset)
      }
      
      if (nzchar(strategy$program %||% "")) {
        updateSelectInput(session, "program", selected = strategy$program)
      }
      
      if (nzchar(strategy$database %||% "")) {
        updateSelectInput(session, "db", selected = strategy$database)
      }
      
      if (nzchar(strategy$evalue %||% "")) {
        updateTextInput(session, "eval", value = as.character(strategy$evalue))
      }
      
      updateCheckboxInput(
        session,
        "show_advanced_params",
        value = isTRUE(strategy$show_advanced_params)
      )
      
      params <- strategy$parameters %||% list()
      
      session$onFlushed(function() {
        for (nm in names(params)) {
          id <- aligner_param_input_id(nm)
          val <- params[[nm]]
          
          if (is.null(val)) next
          
          updateTextInput(session, id, value = as.character(val))
          updateNumericInput(session, id, value = suppressWarnings(as.numeric(val)))
          updateSelectInput(session, id, selected = as.character(val))
        }
        
        pending_strategy(NULL)
        showNotification("Search strategy loaded.", type = "message")
      }, once = TRUE)
    },
    ignoreInit = TRUE
  )
  
  # ---- Load alignment XML from file ----
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
    render_alignment_results_dt(df = df, subject_meta = subject_meta())
  })
  
  # ---- Clicked row summary ----
  output$clicked <- renderTable({
    sel <- input$alignmentResults_rows_selected
    req(length(sel) == 1)
    
    df <- parsedresults()
    row <- df[sel, , drop = FALSE]
    
    render_clicked_summary_table(row = row, subject_meta = subject_meta())
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
        subject_meta = subject_meta()
      )
    }
  )
  
  # ---- Download raw alignment XML ----
  output$download_xml <- downloadHandler(
    filename = function() paste0("align_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xml"),
    content = function(file) {
      doc <- isolate(xml_current())
      validate(need(!is.null(doc), "No alignment XML available"))
      saveXML(doc, file = file)
    }
  )
  
  output$download_strategy <- downloadHandler(
    filename = function() {
      paste0("localignr_search_strategy_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json")
    },
    content = function(file) {
      aligner <- toupper(input$aligner %||% "BLAST")
      program <- input$program %||% NULL
      
      params <- collect_aligner_params(
        input = input,
        aligner = aligner,
        program = program
      )
      
      strategy <- build_search_strategy(
        input = input,
        params = params
      )
      
      write_search_strategy(strategy, file)
    }
  )
  
  # ---- Build local sequence DB ----
  make_log <- reactiveVal("")
  append_make_log <- function(...) {
    msg <- sprintf(...)
    old <- make_log()
    make_log(paste0(old, if (nzchar(old)) "\n" else "", msg))
  }
  
  output$make_log <- renderText(make_log())
  
  # ---- Output-directory chooser for DB building ----
  make_dir_roots <- build_shinyfiles_volumes()
  
  shinyFiles::shinyDirChoose(
    input = input,
    id = "make_outdir_browse",
    roots = make_dir_roots,
    session = session,
    allowDirCreate = TRUE
  )
  
  observeEvent(input$make_outdir_browse, {
    sel <- tryCatch(
      shinyFiles::parseDirPath(make_dir_roots, input$make_outdir_browse),
      error = function(e) character(0)
    )
    
    if (length(sel) == 1 && !is.na(sel) && nzchar(sel)) {
      updateTextInput(
        session = session,
        inputId = "make_outdir",
        value = normalizePath(sel, winslash = "/", mustWork = FALSE)
      )
    }
  }, ignoreInit = TRUE)
  
  observeEvent(input$make_run, {
    run_makeblastdb_and_register(
      input = input,
      cfg = cfg,
      db_registry = db_registry,
      allowed_db_fun = function(program) allowed_db_choices(program, aligner = "BLAST"),
      session = session,
      append_log = append_make_log
    )
    
    rm(list = ls(envir = metadata_cache), envir = metadata_cache)
    logf("[META] Metadata cache cleared after DB registration")
  })
  
  observeEvent(input$upload_strategy, {
    req(
      is.list(input$upload_strategy),
      nzchar(input$upload_strategy$datapath),
      file.exists(input$upload_strategy$datapath)
    )
    
    strategy <- tryCatch(
      read_search_strategy(input$upload_strategy$datapath),
      error = function(e) {
        showNotification(
          paste("Could not load search strategy:", e$message),
          type = "error"
        )
        NULL
      }
    )
    
    req(!is.null(strategy))
    
    pending_strategy(strategy)
    
    updateSelectInput(
      session,
      "aligner",
      selected = toupper(strategy$aligner %||% "BLAST")
    )
  })
}
