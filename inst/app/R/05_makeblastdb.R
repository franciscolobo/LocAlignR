# R/05_makeblastdb.R

run_makeblastdb_and_register <- function(input,
                                        cfg,
                                        db_registry,
                                        allowed_db_fun,
                                        session,
                                        append_log) {
  shiny::validate(shiny::need(nzchar(Sys.which("makeblastdb")), "makeblastdb not found on PATH"))
  shiny::validate(shiny::need(is.list(input$make_fasta) && file.exists(input$make_fasta$datapath), "Choose a FASTA file"))
  shiny::validate(shiny::need(nzchar(input$make_name), "Provide a database name"))
  shiny::validate(shiny::need(input$make_type %in% c("prot", "nucl"), "Choose a valid type"))

  outdir <- if (nzchar(input$make_outdir)) input$make_outdir else getwd()
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

  outbase <- normalizePath(file.path(outdir, input$make_name), winslash = "/", mustWork = FALSE)

  args <- c(
    "-in", normalizePath(input$make_fasta$datapath, winslash = "/"),
    "-dbtype", input$make_type,
    "-out", outbase
  )

  if (isTRUE(input$make_parse)) args <- c(args, "-parse_seqids")
  if (nzchar(input$make_title)) args <- c(args, "-title", input$make_title)

  append_log("[makeblastdb] cmd: makeblastdb %s", paste(shQuote(args), collapse = " "))

  # Conda-first tool discovery: prefer PATH, allow override via LOCALIGN_MAKEBLASTDB
  makeblastdb_path <- LocAlignR::localignr_find_tool("makeblastdb", env_var = "LOCALIGN_MAKEBLASTDB")

  validate(
    need(
      nzchar(makeblastdb_path),
      "makeblastdb not found. Activate the conda environment (preferred) or set LOCALIGN_MAKEBLASTDB."
    )
  )

  res <- processx::run(makeblastdb_path, args, error_on_status = FALSE, timeout = 1800, echo = FALSE)

  append_log("[makeblastdb] exit status: %d", res$status)
  if (nzchar(res$stdout)) append_log(res$stdout)
  if (nzchar(res$stderr)) append_log(res$stderr)

  shiny::validate(shiny::need(res$status == 0, "makeblastdb failed"))

  # Update in-memory registry
  reg <- db_registry()
  new_row <- data.frame(
    name = input$make_name,
    path = outbase,
    type = input$make_type,
    stringsAsFactors = FALSE
  )
  reg <- rbind(reg[reg$name != input$make_name, ], new_row)
  db_registry(reg)

  # Persist only user DBs (exclude seed names from config)
  seed_names <- names(cfg$databases)
  user_save <- reg[!(reg$name %in% seed_names), , drop = FALSE]
  save_user_dbs(user_save)

  # Refresh selector
  choices <- unique(allowed_db_fun(input$program))
  if (!(input$make_name %in% choices)) choices <- c(input$make_name, choices)
  updateSelectInput(session, "db", choices = choices, selected = input$make_name)

  append_log(
    "[makeblastdb] Registered and saved DB '%s' at %s (type=%s)",
    input$make_name, outbase, input$make_type
  )
  append_log("[makeblastdb] Registry file: %s", user_db_file)
}
