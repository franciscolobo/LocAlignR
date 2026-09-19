# inst/app/R/90_diagnostics.R
# Wires diagnostics outputs into the Shiny server.

wire_diagnostics <- function(input, output, db_registry) {

  tool_report <- function(tool, env_var, args) {
    p <- LocAlignR::localignr_find_tool(tool, env_var = env_var)
    if (!nzchar(p)) {
      return(paste0("NOT FOUND (activate conda env or set ", env_var, ")"))
    }

    # Use system2 for lightweight version checks
    v <- tryCatch(
      system2(p, args = args, stdout = TRUE, stderr = TRUE),
      error = function(e) paste0("ERROR: ", e$message)
    )

    paste(c(paste0("Path: ", p), "Version:", v), collapse = "\n")
  }

  output$diag_blast <- shiny::renderText({
    tool_report("blastp", "LOCALIGN_BLASTP", "-version")
  })

  output$diag_makeblastdb <- shiny::renderText({
    tool_report("makeblastdb", "LOCALIGN_MAKEBLASTDB", "-version")
  })

  output$diag_diamond <- shiny::renderText({
    tool_report("diamond", "LOCALIGN_DIAMOND", "version")
  })

  output$diag_session <- shiny::renderText({
    paste(
      c(
        paste0("R: ", R.version.string),
        paste0("Platform: ", R.version$platform),
        paste0("Detected CPU threads: ", parallel::detectCores(logical = TRUE) %||% NA),
        paste0("Working directory: ", normalizePath(getwd(), winslash = "/", mustWork = FALSE))
      ),
      collapse = "\n"
    )
  })

  # ---- R package versions ----
  output$diag_packages <- shiny::renderText({
    pkgs <- c(
      "shiny", "shinythemes", "DT", "shinyFiles",
      "shinybusy", "XML", "plyr", "dplyr",
      "yaml", "processx", "digest", "htmltools", "htmlwidgets",
      "openxlsx"
    )

    lines <- vapply(pkgs, function(p) {
      if (requireNamespace(p, quietly = TRUE)) {
        sprintf("%-14s %s", p, as.character(utils::packageVersion(p)))
      } else {
        sprintf("%-14s NOT INSTALLED", p)
      }
    }, character(1))

    paste(lines, collapse = "\n")
  })

  # ---- Conda environment ----
  output$diag_conda <- shiny::renderText({
    prefix   <- Sys.getenv("CONDA_PREFIX", unset = "")
    env_name <- Sys.getenv("CONDA_DEFAULT_ENV", unset = "")

    lines <- c(
      paste0("CONDA_DEFAULT_ENV: ", if (nzchar(env_name)) env_name else "<not set>"),
      paste0("CONDA_PREFIX: ", if (nzchar(prefix)) prefix else "<not set>")
    )

    if (!nzchar(prefix)) {
      lines <- c(
        lines,
        "",
        "Note: LocAlignR expects BLAST/DIAMOND from an activated conda",
        "environment. With no environment active, tools are resolved via",
        "PATH or the LOCALIGN_* environment variable overrides instead."
      )
    }

    paste(lines, collapse = "\n")
  })

  # ---- Configuration file locations ----
  output$diag_config_paths <- shiny::renderText({
    paths <- c(
      "User preferences" = user_preferences_file,
      "User databases"   = user_db_file
    )

    lines <- vapply(names(paths), function(nm) {
      p <- paths[[nm]]
      sprintf(
        "%-18s %s  [%s]",
        nm, p, if (file.exists(p)) "exists" else "not yet created"
      )
    }, character(1))

    paste(lines, collapse = "\n")
  })

  # ---- Storage / temp directory ----
  output$diag_storage <- shiny::renderText({
    td <- tempdir()

    writable <- tryCatch({
      test_file <- file.path(td, paste0(".localignr_write_test_", Sys.getpid()))
      writeLines("test", test_file)
      unlink(test_file)
      TRUE
    }, error = function(e) FALSE)

    paste(
      c(
        paste0("Temp directory: ", td),
        paste0(
          "Writable: ",
          if (writable) "yes" else "NO - alignment runs will fail to write output"
        )
      ),
      collapse = "\n"
    )
  })

  # ---- Database registry health ----
  output$diag_db_health <- shiny::renderText({
    reg <- db_registry()

    if (is.null(reg) || !nrow(reg)) {
      return("No databases registered.")
    }

    local_rows <- reg[!(reg$path %in% c("nr", "nt")), , drop = FALSE]
    missing <- local_rows[!file.exists(local_rows$path), , drop = FALSE]

    lines <- c(
      sprintf("Registered databases: %d", nrow(reg)),
      sprintf("Missing/broken paths: %d", nrow(missing))
    )

    if (nrow(missing)) {
      lines <- c(
        lines,
        "",
        "Broken entries (path no longer exists on disk):",
        sprintf("  - %s -> %s", missing$name, missing$path)
      )
    }

    paste(lines, collapse = "\n")
  })

  # ---- Recent log output (manual refresh) ----
  log_tail_trigger <- shiny::reactiveVal(0)

  shiny::observeEvent(input$diag_refresh_log, {
    log_tail_trigger(log_tail_trigger() + 1)
  })

  output$diag_log_tail <- shiny::renderText({
    log_tail_trigger()  # reactive dependency only; value itself unused

    log_file <- LocAlignR::localignr_log_file()

    if (!file.exists(log_file)) {
      return(paste0("Log file not found: ", log_file))
    }

    lines <- readLines(log_file, warn = FALSE)
    n_total <- length(lines)
    tail_lines <- utils::tail(lines, 40)

    paste(
      c(
        paste0(
          "Log file: ", log_file,
          " (", n_total, " lines total, showing last ", length(tail_lines), ")"
        ),
        "",
        tail_lines
      ),
      collapse = "\n"
    )
  })
}


