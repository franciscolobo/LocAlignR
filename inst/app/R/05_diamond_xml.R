# inst/app/R/06_diamond_xml.R

run_diamond_as_xml <- function(mode, query, db, eval, params = list()) {
  mode <- match.arg(mode, c("blastp", "blastx"))
  
  diamond_path <- LocAlignR::localignr_find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
  
  shiny::validate(
    shiny::need(
      nzchar(diamond_path),
      "diamond not found. Activate the conda environment (preferred) or set LOCALIGN_DIAMOND."
    )
  )
  
  max_target_seqs <- as.integer(params$max_target_seqs %||% 10L)
  threads <- as.integer(params$threads %||% max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
  timeout <- as.integer(params$timeout_sec %||% 600L)
  
  sensitivity <- params$sensitivity %||% "default"
  sensitivity <- as.character(sensitivity)
  
  if (length(sensitivity) == 0 || is.na(sensitivity) || !nzchar(trimws(sensitivity))) {
    sensitivity <- "default"
  }
  
  sensitivity <- trimws(sensitivity)
  
  valid_sensitivity <- c(
    "default",
    "sensitive",
    "more-sensitive",
    "very-sensitive",
    "ultra-sensitive"
  )
  
  shiny::validate(
    shiny::need(
      sensitivity %in% valid_sensitivity,
      paste("Invalid DIAMOND sensitivity:", sensitivity)
    )
  )
  
  top <- params$top %||% NULL
  block_size <- params$block_size %||% NULL
  index_chunks <- params$index_chunks %||% NULL
  
  out_xml <- tempfile(pattern = "diamond_", fileext = ".xml")
  
  args <- c(
    mode,
    "--query", query,
    "--db", db,
    "--evalue", as.character(eval),
    "--max-target-seqs", as.character(max_target_seqs),
    "--threads", as.character(threads),
    "--out", out_xml,
    "--outfmt", "5"
  )
  
  if (!identical(sensitivity, "default")) {
    args <- c(args, paste0("--", sensitivity))
  }
  
  if (!is.null(top)) {
    args <- c(args, "--top", as.character(top))
  }
  
  if (!is.null(block_size)) {
    args <- c(args, "--block-size", as.character(block_size))
  }
  
  if (!is.null(index_chunks)) {
    args <- c(args, "--index-chunks", as.character(as.integer(index_chunks)))
  }
  
  logf("[DIAMOND] cmd: %s %s", diamond_path, paste(shQuote(args), collapse = " "))
  
  res <- processx::run(
    diamond_path,
    args,
    error_on_status = FALSE,
    timeout = timeout,
    echo = FALSE
  )
  
  logf("[DIAMOND] exit status: %s", res$status)
  if (nzchar(res$stdout)) logf("[DIAMOND] stdout: %s", res$stdout)
  if (nzchar(res$stderr)) logf("[DIAMOND] stderr: %s", res$stderr)
  logf(
    "[DIAMOND] out_xml exists=%s size=%s",
    file.exists(out_xml),
    if (file.exists(out_xml)) file.size(out_xml) else NA
  )
  
  shiny::validate(
    shiny::need(res$status == 0, paste("DIAMOND failed:", res$stderr)),
    shiny::need(file.exists(out_xml) && file.size(out_xml) > 0, "DIAMOND produced no XML output.")
  )
  
  XML::xmlParse(out_xml, useInternalNodes = TRUE)
}