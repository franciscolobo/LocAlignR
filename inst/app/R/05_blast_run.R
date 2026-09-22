# The only function in the codebase that actually shells out to a BLAST+
# binary. Everything else related to BLAST results (parsing, rendering,
# export) is aligner-agnostic and lives in 04_alignment_results.R, because
# DIAMOND's --outfmt 5 output uses the same XML schema.

# Pure argument-building logic, extracted out of run_blast_as_xml() so it
# can be unit tested directly with no mocking -- no tool discovery, no
# process execution, no filesystem I/O beyond the already-existing
# out_xml path string itself (which is never written to here).
build_blast_args <- function(prog, query, db, eval, remote, params = list(), out_xml) {
  max_target_seqs <- as.integer(params$max_target_seqs %||% 10L)
  threads <- as.integer(params$threads %||% max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
  max_hsps <- as.integer(params$max_hsps %||% 1L)
  culling_limit <- params$culling_limit %||% NULL
  best_hit_overhang <- params$best_hit_overhang %||% NULL
  best_hit_score_edge <- params$best_hit_score_edge %||% NULL
  word_size <- params$word_size %||% NULL
  matrix <- params$matrix %||% NULL
  gapopen <- params$gapopen %||% NULL
  gapextend <- params$gapextend %||% NULL

  args <- c(
    "-query", query,
    "-db", db,
    "-evalue", as.character(eval),
    "-outfmt", "5",
    "-out", out_xml,
    "-max_hsps", as.character(max_hsps),
    "-max_target_seqs", as.character(max_target_seqs)
  )

  if (!is.null(word_size) && length(word_size) > 0 && !is.na(word_size)) {
    args <- c(args, "-word_size", as.character(as.integer(word_size)))
  }

  if (!is.null(matrix) && length(matrix) > 0 && !is.na(matrix) && nzchar(trimws(as.character(matrix)))) {
    args <- c(args, "-matrix", as.character(matrix))
  }

  if (!is.null(gapopen) && length(gapopen) > 0 && !is.na(gapopen)) {
    args <- c(args, "-gapopen", as.character(as.integer(gapopen)))
  }

  if (!is.null(gapextend) && length(gapextend) > 0 && !is.na(gapextend)) {
    args <- c(args, "-gapextend", as.character(as.integer(gapextend)))
  }

  if (!is.null(culling_limit) && length(culling_limit) > 0 && !is.na(culling_limit)) {
    args <- c(args, "-culling_limit", as.character(as.integer(culling_limit)))
  }

  has_best_hit_overhang <- !is.null(best_hit_overhang) &&
    length(best_hit_overhang) > 0 &&
    !is.na(best_hit_overhang)

  has_best_hit_score_edge <- !is.null(best_hit_score_edge) &&
    length(best_hit_score_edge) > 0 &&
    !is.na(best_hit_score_edge)

  if (xor(has_best_hit_overhang, has_best_hit_score_edge)) {
    shiny::validate(
      shiny::need(
        FALSE,
        "BLAST best-hit filtering requires both best-hit overhang and best-hit score edge."
      )
    )
  }

  if (has_best_hit_overhang && has_best_hit_score_edge) {
    args <- c(
      args,
      "-best_hit_overhang", as.character(best_hit_overhang),
      "-best_hit_score_edge", as.character(best_hit_score_edge)
    )
  }

  if (isTRUE(remote)) {
    args <- c(args, "-remote")
  } else {
    args <- c(args, "-num_threads", as.character(threads))
  }

  args
}

run_blast_as_xml <- function(prog, query, db, eval, remote, params = list()) {
  timeout <- as.integer(params$timeout_sec %||% 1800L)

  out_xml <- tempfile(pattern = "blast_", fileext = ".xml")

  args <- build_blast_args(
    prog = prog, query = query, db = db, eval = eval,
    remote = remote, params = params, out_xml = out_xml
  )

  prog_path <- LocAlignR::localignr_find_tool(
    prog,
    env_var = paste0("LOCALIGN_", toupper(prog))
  )

  message(sprintf("[BLAST] program=%s", prog))
  message(sprintf("[BLAST] executable=%s", prog_path))
  message(sprintf("[BLAST] query=%s", query))
  message(sprintf("[BLAST] db=%s", db))
  message(sprintf("[BLAST] args=%s", paste(shQuote(args), collapse = " ")))

  shiny::validate(
    shiny::need(
      nzchar(prog_path),
      paste0(
        prog,
        " not found. Activate the conda environment or set ",
        paste0("LOCALIGN_", toupper(prog)),
        "."
      )
    )
  )

  res <- run_process_with_progress(
    command       = prog_path,
    args          = args,
    timeout_sec   = timeout,
    progress_text = sprintf("Running %s...", prog)
  )

  message(sprintf("[BLAST] exit status=%s", res$status))
  if (nzchar(res$stderr)) message(sprintf("[BLAST] stderr=%s", res$stderr))
  message(sprintf(
    "[BLAST] out_xml exists=%s size=%s",
    file.exists(out_xml),
    if (file.exists(out_xml)) file.size(out_xml) else NA
  ))

  shiny::validate(
    shiny::need(
      !isTRUE(res$timed_out),
      sprintf("BLAST timed out after %d seconds.", timeout)
    ),
    shiny::need(
      !is.na(res$status) && res$status == 0,
      paste0(
        "BLAST failed.\n\nProgram: ", prog,
        "\nExit status: ", res$status,
        "\n\nSTDERR:\n", res$stderr
      )
    ),
    shiny::need(
      file.exists(out_xml) && file.size(out_xml) > 0,
      paste0("BLAST produced no XML output.\n\nSTDERR:\n", res$stderr)
    )
  )

  XML::xmlParse(out_xml, useInternalNodes = TRUE)
}
