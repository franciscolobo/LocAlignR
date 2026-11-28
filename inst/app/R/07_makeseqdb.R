# R/06_makeblastdb.R

run_makeseqdb_and_register <- function(
    input,
    cfg,
    db_registry,
    allowed_db_fun,
    session,
    append_log,
    taxonomy = NULL
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
  db_label <- trimws(input$make_name)
  db_name <- make_db_registry_name(db_label, backend)
  
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
  
  # Optional programmatic configuration; the next UI phase will supply this list.
  # Existing callers omit it and follow the unchanged non-taxonomy path.
  taxonomy_enabled <- !is.null(taxonomy)
  taxonomy_build <- NULL
  stage <- NULL
  published <- FALSE
  registered <- FALSE
  if (taxonomy_enabled) {
    if (!is.list(taxonomy)) stop("Taxonomy configuration must be a list.")
    if (!backend %in% c("blast", "diamond")) stop("Invalid indexing backend.")
    if (!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", db_name) ||
        !endsWith(db_name, paste0("_", backend))) {
      stop("Use a simple database name with the correct backend suffix.")
    }
    if (db_name %in% c(db_registry()$name, names(cfg$databases))) stop("Choose a new database name for taxonomy-aware indexing.")
    final_dir <- file.path(outdir, db_name)
    if (file.exists(final_dir) || dir.exists(final_dir) ||
        any(startsWith(list.files(outdir, all.files = TRUE), paste0(db_name, ".")))) {
      stop("Database output already exists; choose a new database name.")
    }
    stage <- tempfile(".localignr-build-", tmpdir = outdir)
    if (!dir.create(stage)) stop("Cannot create database staging directory.")
    stage <- normalizePath(stage, winslash = "/", mustWork = TRUE)
    on.exit({
      unlink(stage, recursive = TRUE)
      if (published && !registered) unlink(final_dir, recursive = TRUE)
    }, add = TRUE)
    taxonomy_build <- localignr_taxonomy_prepare_build(
      fasta = fasta_path, backend = backend, directory = stage,
      method = taxonomy$method %||% "uniprot", taxid = taxonomy$taxid,
      mapping_path = taxonomy$mapping_path, taxonomy_dir = taxonomy$taxonomy_dir
    )
    append_log("[taxonomy] Validated %d sequence-to-TaxID assignments against %s",
               nrow(taxonomy_build$mapping), taxonomy_build$taxonomy_snapshot)
    outbase <- file.path(stage, db_name)
  }

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
      "--db", if (taxonomy_enabled) basename(outbase) else outbase
    )
    
    if (taxonomy_enabled) args <- c(args, taxonomy_build$args)

    append_log("[diamond makedb] cmd: %s %s", diamond_path, paste(shQuote(args), collapse = " "))
    
    res <- processx::run(
      diamond_path,
      args,
      error_on_status = FALSE,
      timeout = 1800,
      wd = if (taxonomy_enabled) stage else getwd(),
      echo = FALSE
    )
    
    append_log("[diamond makedb] exit status: %d", res$status)
    if (nzchar(res$stdout)) append_log("%s", res$stdout)
    if (nzchar(res$stderr)) append_log("%s", res$stderr)
    
    shiny::validate(
      shiny::need(res$status == 0, "diamond makedb failed")
    )
    
    if (taxonomy_enabled) {
      localignr_taxonomy_validate_diamond_log(res$stdout, res$stderr, nrow(taxonomy_build$mapping))
    }

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
      "-out", if (taxonomy_enabled) basename(outbase) else outbase
    )
    
    if (taxonomy_enabled) {
      args <- c(args, taxonomy_build$args)
    } else if (isTRUE(input$make_parse)) {
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
      wd = if (taxonomy_enabled) stage else getwd(),
      echo = FALSE
    )
    
    append_log("[makeblastdb] exit status: %d", res$status)
    if (nzchar(res$stdout)) append_log("%s", res$stdout)
    if (nzchar(res$stderr)) append_log("%s", res$stderr)
    
    shiny::validate(
      shiny::need(res$status == 0, "makeblastdb failed")
    )
    
    db_path <- outbase
    if (taxonomy_enabled) {
      # Check that BLAST really indexed the expected number of taxonomic assignments.
      blastdbcmd <- LocAlignR::localignr_find_tool("blastdbcmd", env_var = "LOCALIGN_BLASTDBCMD")
      if (!nzchar(blastdbcmd)) stop("blastdbcmd is required to validate taxonomy-aware BLAST builds.")
      check <- processx::run(blastdbcmd, c("-db", db_path, "-entry", "all", "-outfmt", "%T"),
                             error_on_status = FALSE, timeout = 1800, echo = FALSE)
      ids <- trimws(strsplit(check$stdout, "\n", fixed = TRUE)[[1]])
      ids <- ids[nzchar(ids)]
      if (check$status != 0L || !identical(sort(ids), sort(taxonomy_build$mapping$taxid))) {
        stop("BLAST indexed TaxID counts differ from the validated input mapping.")
      }
    }
  }
  
  reg <- normalize_registry_df(db_registry())
  
  metadata_path <- ""
  has_metadata <- FALSE
  
  if (is.list(input$make_metadata) &&
      !is.null(input$make_metadata$datapath) &&
      nzchar(input$make_metadata$datapath) &&
      file.exists(input$make_metadata$datapath)) {
    
    metadata_ext <- tools::file_ext(input$make_metadata$name)
    metadata_path <- file.path(
      if (taxonomy_enabled) stage else outdir,
      paste0(db_name, "_metadata.", metadata_ext)
    )
    
    if (!file.copy(input$make_metadata$datapath, metadata_path, overwrite = TRUE)) {
      stop("Could not save database metadata.")
    }
    metadata_path <- normalizePath(metadata_path, winslash = "/", mustWork = FALSE)
    has_metadata <- TRUE
  }
  
  taxonomy_map_path <- ""
  if (taxonomy_enabled) {
    if (file.exists(final_dir) || !file.rename(stage, final_dir)) {
      stop("Cannot publish taxonomy-aware database directory.")
    }
    published <- TRUE
    final_dir <- normalizePath(final_dir, winslash = "/", mustWork = TRUE)
    db_path <- file.path(final_dir, basename(db_path))
    taxonomy_map_path <- file.path(final_dir, basename(taxonomy_build$map_path))
    if (has_metadata) metadata_path <- file.path(final_dir, basename(metadata_path))
  }

  new_row <- normalize_registry_df(
    data.frame(
      name = db_name,
      path = db_path,
      type = db_type,
      backend = backend,
      title = trimws(input$make_title %||% db_label),
      source = "user",
      created = as.character(Sys.Date()),
      version = "",
      metadata_path = metadata_path,
      has_metadata = has_metadata,
      has_taxonomy = taxonomy_enabled,
      taxonomy_source = if (taxonomy_enabled) "NCBI" else "",
      taxonomy_dir = if (taxonomy_enabled) taxonomy_build$taxonomy_dir else "",
      taxonomy_snapshot = if (taxonomy_enabled) taxonomy_build$taxonomy_snapshot else "",
      taxonomy_map_path = taxonomy_map_path,
      stringsAsFactors = FALSE
    )
  )
  
  reg <- rbind(reg[reg$name != db_name, , drop = FALSE], new_row)
  
  seed_names <- names(cfg$databases)
  user_save <- reg[!(reg$name %in% seed_names), , drop = FALSE]
  save_user_dbs(user_save)
  registered <- TRUE
  db_registry(reg)
  
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