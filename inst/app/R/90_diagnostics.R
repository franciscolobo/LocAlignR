# inst/app/R/90_diagnostics.R
# Wires diagnostics outputs into the Shiny server.

wire_diagnostics <- function(output) {

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
        paste0("Working directory: ", normalizePath(getwd(), winslash = "/", mustWork = FALSE))
      ),
      collapse = "\n"
    )
  })
}
