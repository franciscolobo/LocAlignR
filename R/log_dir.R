# R/log_dir.R
#
# Cross-platform log location for LocAlignR.
#
# Previously R/run_app.R hardcoded "~/Library/Logs/LocAlignR", a macOS-only
# convention, even though LocAlignR supports Windows and Linux. This uses
# tools::R_user_dir(..., which = "cache") instead, which resolves correctly
# per-platform (e.g. ~/Library/Caches on macOS, %LOCALAPPDATA% on Windows,
# ~/.cache on Linux/XDG) -- mirroring the "config" location already used for
# user_preferences.yml and user_dbs.yml in inst/app/R/02_user_db_registry.R
# and inst/app/R/11_user_preferences.R.

#' Resolve the LocAlignR log directory (cross-platform).
#'
#' @return A normalized directory path. The directory is not created by this
#'   function; callers should dir.create(..., recursive = TRUE) as needed.
#' @export
localignr_log_dir <- function() {
  file.path(tools::R_user_dir("LocAlignR", which = "cache"), "logs")
}

#' Path to the LocAlignR startup log file.
#' @export
localignr_log_file <- function() {
  file.path(localignr_log_dir(), "app_startup.log")
}
