# inst/app/R/06_diamond_xml.R

run_diamond_as_xml <- function(mode, query, db, eval, max_target_seqs = 10L, timeout = 600) {
  mode <- match.arg(mode, c("blastp", "blastx"))

  diamond_path <- LocAlign::localign_find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
  shiny::validate(
    shiny::need(
      nzchar(diamond_path),
      "diamond not found. Activate the conda environment (preferred) or set LOCALIGN_DIAMOND."
    )
  )

  threads <- as.integer(max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
  out_xml <- tempfile(pattern = "diamond_", fileext = ".xml")

  args <- c(
    mode,
    "--query", query,
    "--db", db,
    "--evalue", as.character(eval),
    "--max-target-seqs", as.character(as.integer(max_target_seqs)),
    "--threads", as.character(threads),
    "--out", out_xml,
    "--outfmt", "5"
  )

  res <- processx::run(diamond_path, args, error_on_status = FALSE, timeout = timeout, echo = FALSE)

  shiny::validate(
    shiny::need(res$status == 0, paste("DIAMOND failed:", res$stderr)),
    shiny::need(file.exists(out_xml) && file.size(out_xml) > 0, "DIAMOND produced no XML output.")
  )

  XML::xmlParse(out_xml, useInternalNodes = TRUE)
}

