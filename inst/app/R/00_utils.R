# R/00_utils.R

`%||%` <- function(a, b) if (!is.null(a)) a else b

logf <- function(...) message(sprintf(...))

build_shinyfiles_volumes <- function() {
  c(
    Home = normalizePath("~", winslash = "/", mustWork = TRUE),
    `Working Dir` = normalizePath(getwd(), winslash = "/", mustWork = TRUE),
    shinyFiles::getVolumes()()
  )
}


#' Run an external command asynchronously with a live, time-based progress bar.
#'
#' Neither BLAST+ nor DIAMOND report machine-readable completion percentage in
#' XML output mode, so this drives an *estimated* progress bar from elapsed
#' time (asymptotic curve, capped below 100% until the process actually
#' exits). This is deliberately conservative: it under-promises early and
#' catches up once the job finishes, rather than lying about exact progress.
#'
#' Stdout/stderr are captured to files rather than pipes to avoid a pipe-
#' buffer deadlock on large XML output (a real risk once alignment stdout
#' exceeds the OS pipe buffer, ~64KB on Linux, if nothing drains it while the
#' process is still writing).
#'
#' @param command Path to the executable.
#' @param args Character vector of arguments.
#' @param timeout_sec Hard timeout; process is killed if exceeded.
#' @param progress_text Label shown above the progress bar.
#' @param poll_interval Seconds between polls/UI updates.
#' @param tau Time constant controlling how fast the bar approaches its
#'   asymptote. Defaults to timeout_sec / 4 (reaches ~95% around 3*tau).
#' @param stdout_file Optional path to capture stdout into (defaults to a
#'   tempfile). Use this when the aligner itself doesn't write output via
#'   its own `-out`/`--out` flag.
#'
#' @return list(status, stdout, stderr, timed_out), shaped like the relevant
#'   fields of processx::run()'s result.
run_process_with_progress <- function(
    command,
    args,
    timeout_sec,
    progress_text = "Running...",
    poll_interval = 0.4,
    tau = NULL,
    stdout_file = NULL
) {
  tau <- tau %||% max(5, timeout_sec / 4)

  stdout_file <- stdout_file %||% tempfile(pattern = "stdout_", fileext = ".log")
  stderr_file <- tempfile(pattern = "stderr_", fileext = ".log")

  proc <- processx::process$new(
    command = command,
    args = args,
    stdout = stdout_file,
    stderr = stderr_file,
    cleanup = TRUE
  )

  on.exit({
    if (proc$is_alive()) proc$kill()
  }, add = TRUE)

  shinybusy::show_modal_progress_line(value = 0, text = progress_text)
  on.exit(shinybusy::remove_modal_progress(), add = TRUE)

  start_time <- Sys.time()
  timed_out <- FALSE

  repeat {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

    if (!proc$is_alive()) break

    if (elapsed >= timeout_sec) {
      proc$kill()
      timed_out <- TRUE
      break
    }

    pct <- 95 * (1 - exp(-elapsed / tau))

    shinybusy::update_modal_progress(
      value = pct / 100,
      text = sprintf(
        "%s (~%d%%, %ds elapsed)",
        progress_text, round(pct), round(elapsed)
      )
    )

    Sys.sleep(poll_interval)
  }

  shinybusy::update_modal_progress(value = 1, text = "Finalizing...")

  status <- if (timed_out) NA_integer_ else proc$get_exit_status()

  read_log <- function(path) {
    if (file.exists(path)) paste(readLines(path, warn = FALSE), collapse = "\n") else ""
  }

  list(
    status    = status,
    stdout    = read_log(stdout_file),
    stderr    = read_log(stderr_file),
    timed_out = timed_out
  )
}
