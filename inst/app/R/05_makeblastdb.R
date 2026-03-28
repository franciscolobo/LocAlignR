# R/05_makeblastdb.R

run_makeblastdb_and_register <- function(
    input,
    cfg,
    db_registry,
    allowed_db_fun,
    session,
    append_log
) {
  shiny::validate(
    shiny::need(
      is.list(input$make_fasta) && file.exists(input$make_fasta$datapath),
      "Choose a FASTA file."
    ),
    shiny::need(nzchar(trimws(input$make_name)), "Provide a database name."),
    shiny::need(input$make_type %in% c("prot", "nucl"), "Choose a valid database type.")
  )
  
  backend <- tolower(input$make_backend %||% "blast")
  db_type <- input$make_type
  db_name <- trimws(input$make_name)
  
  shiny::validate(
    shiny::need(
      !(identical(backend, "diamond") && !identical(db_type, "prot")),
      "DIAMOND supports only protein databases."
    )
  )
  
  outdir <- trimws(input$make_outdir %||% "")
  if (!nzchar(outdir)) {
    outdir <- getwd()
  }
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  
  fasta_path <- normalizePath(input$make_fasta$datapath, winslash = "/", mustWork = TRUE)
  outbase <- normalizePath(file.path(outdir, db_name), winslash = "/", mustWork = FALSE)
  
  if (identical(backend, "diamond")) {
    diamond_path <- LocAlignR::localignr_find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
    
    shiny::validate(
      shiny::need(
        nzchar(diamond_path),
        "diamond not found. Activate the conda environment or set LOCALIGN_DIAMOND."
      )
    )
    
    args <- c(
      "makedb",
      "--in", fasta_path,
      "--db", outbase
    )
    
    append_log("[diamond makedb] cmd: %s %s", diamond_path, paste(shQuote(args), collapse = " "))
    
    res <- processx::run(
      diamond_path,
      args,
      error_on_status = FALSE,
      timeout = 1800,
      echo = FALSE
    )
    
    append_log("[diamond makedb] exit status: %d", res$status)
    if (nzchar(res$stdout)) append_log(res$stdout)
    if (nzchar(res$stderr)) append_log(res$stderr)
    
    shiny::validate(
      shiny::need(res$status == 0, "diamond makedb failed")
    )
    
    db_path <- paste0(outbase, ".dmnd")
    
    shiny::validate(
      shiny::need(file.exists(db_path), "diamond makedb did not create the expected .dmnd file.")
    )
  } else {
    makeblastdb_path <- LocAlignR::localignr_find_tool("makeblastdb", env_var = "LOCALIGN_MAKEBLASTDB")
    
    shiny::validate(
      shiny::need(
        nzchar(makeblastdb_path),
        "makeblastdb not found. Activate the conda environment or set LOCALIGN_MAKEBLASTDB."
      )
    )
    
    args <- c(
      "-in", fasta_path,
      "-dbtype", db_type,
      "-out", outbase
    )
    
    if (isTRUE(input$make_parse)) {
      args <- c(args, "-parse_seqids")
    }
    if (nzchar(trimws(input$make_title %||% ""))) {
      args <- c(args, "-title", trimws(input$make_title))
    }
    
    append_log("[makeblastdb] cmd: %s %s", makeblastdb_path, paste(shQuote(args), collapse = " "))
    
    res <- processx::run(
      makeblastdb_path,
      args,
      error_on_status = FALSE,
      timeout = 1800,
      echo = FALSE
    )
    
    append_log("[makeblastdb] exit status: %d", res$status)
    if (nzchar(res$stdout)) append_log(res$stdout)
    if (nzchar(res$stderr)) append_log(res$stderr)
    
    shiny::validate(
      shiny::need(res$status == 0, "makeblastdb failed")
    )
    
    db_path <- outbase
  }
  
  reg <- db_registry()
  
  new_row <- data.frame(
    name = db_name,
    path = db_path,
    type = db_type,
    backend = backend,
    stringsAsFactors = FALSE
  )
  
  reg <- rbind(reg[reg$name != db_name, , drop = FALSE], new_row)
  db_registry(reg)
  
  seed_names <- names(cfg$databases)
  user_save <- reg[!(reg$name %in% seed_names), , drop = FALSE]
  save_user_dbs(user_save)
  
  choices <- unique(allowed_db_fun(input$program))
  if (!(db_name %in% choices)) {
    choices <- c(db_name, choices)
  }
  updateSelectInput(session, "db", choices = choices, selected = db_name)
  
  append_log(
    "[db build] Registered and saved DB '%s' at %s (type=%s, backend=%s)",
    db_name, db_path, db_type, backend
  )
  append_log("[db build] Registry file: %s", user_db_file)
}