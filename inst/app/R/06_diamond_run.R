run_diamond_as_xml <- function(mode, query, db, eval, params = list()) {
#  cat("[debug] F. run_diamond_as_xml entered. mode=", mode, " db=", db, "\n")

  mode <- match.arg(mode, c("blastp", "blastx"))
#  cat("[debug] G. mode matched=", mode, "\n")

  diamond_path <- LocAlignR::localignr_find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
#  cat("[debug] H. diamond_path=[", diamond_path, "] nzchar=", nzchar(diamond_path), "\n")

  shiny::validate(
    shiny::need(
      nzchar(diamond_path),
      "diamond not found. Activate the conda environment (preferred) or set LOCALIGN_DIAMOND."
    )
  )
#  cat("[debug] I. diamond_path validate PASSED\n")

  max_target_seqs <- as.integer(params$max_target_seqs %||% 10L)
  threads <- as.integer(params$threads %||% max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
  timeout <- as.integer(params$timeout_sec %||% 600L)
#  cat("[debug] J. max_target_seqs=", max_target_seqs, " threads=", threads, " timeout=", timeout, "\n")

  sensitivity <- params$sensitivity %||% "default"
  sensitivity <- as.character(sensitivity)
#  cat("[debug] K. sensitivity (raw)=[", sensitivity, "]\n")

  if (length(sensitivity) == 0 || is.na(sensitivity) || !nzchar(trimws(sensitivity))) {
    sensitivity <- "default"
  }
  sensitivity <- trimws(sensitivity)
#  cat("[debug] L. sensitivity (final)=[", sensitivity, "]\n")

  valid_sensitivity <- c("default", "sensitive", "more-sensitive", "very-sensitive", "ultra-sensitive")

  shiny::validate(
    shiny::need(
      sensitivity %in% valid_sensitivity,
      paste("Invalid DIAMOND sensitivity:", sensitivity)
    )
  )
#  cat("[debug] M. sensitivity validate PASSED\n")

  top <- params$top %||% NULL
  block_size <- params$block_size %||% NULL
  index_chunks <- params$index_chunks %||% NULL
#  cat("[debug] N. top=", deparse(top), " block_size=", deparse(block_size), " index_chunks=", deparse(index_chunks), "\n")

  out_xml <- tempfile(pattern = "diamond_", fileext = ".xml")
#  cat("[debug] O. out_xml=", out_xml, "\n")

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
  if (!is.null(top)) args <- c(args, "--top", as.character(top))
  if (!is.null(block_size)) args <- c(args, "--block-size", as.character(block_size))
  if (!is.null(index_chunks)) args <- c(args, "--index-chunks", as.character(as.integer(index_chunks)))

#  cat("[debug] P. FULL COMMAND:", diamond_path, paste(shQuote(args), collapse = " "), "\n")

  logf("[DIAMOND] cmd: %s %s", diamond_path, paste(shQuote(args), collapse = " "))
#  cat("[debug] Q. past logf, about to call run_process_with_progress\n")

  res <- run_process_with_progress(
    command       = diamond_path,
    args          = args,
    timeout_sec   = timeout,
    progress_text = sprintf("Running DIAMOND %s...", mode)
  )
#  cat("[debug] R. run_process_with_progress RETURNED. status=", res$status, " timed_out=", res$timed_out, "\n")

  logf("[DIAMOND] exit status: %s", res$status)
  if (nzchar(res$stdout)) logf("[DIAMOND] stdout: %s", res$stdout)
  if (nzchar(res$stderr)) logf("[DIAMOND] stderr: %s", res$stderr)
  logf(
    "[DIAMOND] out_xml exists=%s size=%s",
    file.exists(out_xml),
    if (file.exists(out_xml)) file.size(out_xml) else NA
  )

  shiny::validate(
    shiny::need(
      !isTRUE(res$timed_out),
      sprintf("DIAMOND timed out after %d seconds.", timeout)
    ),
    shiny::need(!is.na(res$status) && res$status == 0, paste("DIAMOND failed:", res$stderr)),
    shiny::need(file.exists(out_xml) && file.size(out_xml) > 0, "DIAMOND produced no XML output.")
  )

  XML::xmlParse(out_xml, useInternalNodes = TRUE)
}

