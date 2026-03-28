# inst/app/R/05_makeblastdb.R

run_makeblastdb_and_register <- function(
    input,
    cfg,
    db_registry,
    allowed_db_fun,
    session,
    append_log
) {
  req(nzchar(input$make_name), nzchar(input$make_fasta))
  
  name <- trimws(input$make_name)
  fasta <- normalizePath(input$make_fasta, mustWork = TRUE)
  
  type <- match.arg(input$make_type, c("nucl", "prot"))
  backend <- tolower(input$make_backend %||% "blast")
  
  shiny::validate(
    shiny::need(
      !(identical(backend, "diamond") && !identical(type, "prot")),
      "DIAMOND supports only protein databases."
    )
  )
  
  outdir <- normalizePath(input$make_outdir %||% ".", mustWork = FALSE)
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  
  if (backend == "diamond") {
    append_log("Running DIAMOND makedb...")
    
    diamond_path <- LocAlignR::localignr_find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
    
    shiny::validate(
      shiny::need(nzchar(diamond_path), "diamond not found in PATH or LOCALIGN_DIAMOND.")
    )
    
    db_path <- file.path(outdir, name)
    
    args <- c(
      "makedb",
      "--in", fasta,
      "--db", db_path
    )
    
    res <- processx::run(diamond_path, args, error_on_status = FALSE)
    
    shiny::validate(
      shiny::need(res$status == 0, paste("diamond makedb failed:", res$stderr))
    )
    
    db_file <- paste0(db_path, ".dmnd")
    
  } else {
    append_log("Running makeblastdb...")
    
    makeblastdb_path <- LocAlignR::localignr_find_tool("makeblastdb", env_var = "LOCALIGN_MAKEBLASTDB")
    
    shiny::validate(
      shiny::need(nzchar(makeblastdb_path), "makeblastdb not found.")
    )
    
    db_path <- file.path(outdir, name)
    
    args <- c(
      "-in", fasta,
      "-dbtype", type,
      "-out", db_path
    )
    
    res <- processx::run(makeblastdb_path, args, error_on_status = FALSE)
    
    shiny::validate(
      shiny::need(res$status == 0, paste("makeblastdb failed:", res$stderr))
    )
    
    db_file <- db_path
  }
  
  append_log("Registering database...")
  
  reg <- db_registry()
  
  new_row <- data.frame(
    name = name,
    path = db_file,
    type = type,
    backend = backend,
    stringsAsFactors = FALSE
  )
  
  reg <- reg[reg$name != name, , drop = FALSE]
  reg <- rbind(reg, new_row)
  
  save_user_dbs(reg)
  db_registry(reg)
  
  append_log(sprintf("Database '%s' registered (%s)", name, backend))
  
  updateSelectInput(session, "db", choices = reg$name, selected = name)
}