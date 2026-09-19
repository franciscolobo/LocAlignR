# inst/app/R/91_databases.R
# Wires the Databases tab (registry browser + removal) into the Shiny server.

wire_databases <- function(input, output, session, db_registry, cfg, allowed_db_choices) {

  # Registry + a per-row on-disk status check, reused by both the table and
  # the removal handler so they always agree on what's currently shown.
  registry_display <- reactive({
    reg <- db_registry()
    if (is.null(reg) || !nrow(reg)) return(reg)

    status <- vapply(seq_len(nrow(reg)), function(i) {
      p <- reg$path[i]

      if (p %in% c("nr", "nt")) {
        return("remote")
      }

      # BLAST DBs are a family of files sharing a base name (.pin/.phr/.nin,
      # or .din etc for nucl); DIAMOND DBs are a single .dmnd file. Checking
      # a few common suffixes avoids false "MISSING" on a valid BLAST DB
      # base path that itself isn't a literal file.
      candidates <- c(p, paste0(p, c(".dmnd", ".pin", ".phr", ".nin")))
      if (any(file.exists(candidates))) "OK" else "MISSING"
    }, character(1))

    cbind(reg, status = status, stringsAsFactors = FALSE)
  })

  output$databasesTable <- DT::renderDT({
    df <- registry_display()
    req(!is.null(df), nrow(df) > 0)

    display <- df[, c(
      "name", "title", "type", "backend", "source",
      "created", "version", "has_metadata", "status", "path"
    )]

    DT::datatable(
      display,
      colnames = c(
        "Name", "Title", "Type", "Backend", "Source", "Created",
        "Version", "Has metadata", "Status", "Path"
      ),
      selection = "multiple",
      filter = "top",
      options = list(pageLength = 10, scrollX = TRUE)
    )
  })

  remove_status <- reactiveVal(
    "Select one or more non-built-in databases above, then click Remove."
  )

  output$db_remove_status <- renderText(remove_status())

  observeEvent(input$db_remove_selected, {
    sel <- input$databasesTable_rows_selected
    df  <- isolate(registry_display())

    if (is.null(sel) || !length(sel) || is.null(df) || !nrow(df)) {
      remove_status("No rows selected.")
      return(invisible(NULL))
    }

    selected_rows <- df[sel, , drop = FALSE]

    seed_selected <- selected_rows[selected_rows$source == "seed", , drop = FALSE]
    removable     <- selected_rows[selected_rows$source != "seed", , drop = FALSE]

    if (!nrow(removable)) {
      remove_status(
        "Selected entry(ies) are built-in (seed) databases from config.yml and cannot be removed here."
      )
      return(invisible(NULL))
    }

    reg <- db_registry()
    reg_new <- reg[!(reg$name %in% removable$name), , drop = FALSE]
    db_registry(reg_new)

    seed_names <- names(cfg$databases)
    user_save  <- reg_new[!(reg_new$name %in% seed_names), , drop = FALSE]
    save_user_dbs(user_save)

    # Keep the run panel's DB dropdown in sync, mirroring how
    # run_makeseqdb_and_register() already refreshes it after registering
    # a new database.
    aligner <- toupper(input$aligner %||% "BLAST")
    choices <- unique(allowed_db_choices(input$program, aligner))

    if (length(choices)) {
      selected <- if (isTRUE(input$db %in% choices)) input$db else choices[1]
      updateSelectInput(session, "db", choices = choices, selected = selected)
    }

    msg <- sprintf(
      "Removed %d database(s): %s",
      nrow(removable), paste(removable$name, collapse = ", ")
    )

    if (nrow(seed_selected)) {
      msg <- paste0(
        msg,
        sprintf(
          "\nSkipped %d built-in database(s) (cannot remove): %s",
          nrow(seed_selected), paste(seed_selected$name, collapse = ", ")
        )
      )
    }

    remove_status(msg)
  })
}

