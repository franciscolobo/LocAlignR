# R/find_tool.R
# Conda-first, cross-platform tool discovery:
#   1) PATH (Sys.which) [preferred]
#   2) Optional env var override (e.g. LOCALIGN_MAKEBLASTDB)
# Returns a normalized absolute path or "".

localign_find_tool <- function(tool, env_var = NULL) {
  is_windows <- identical(.Platform$OS.type, "windows")

  normalize_tool_name <- function(x) {
    if (is_windows && !grepl("\\.exe$", x, ignore.case = TRUE)) paste0(x, ".exe") else x
  }

  is_executable_file <- function(path) {
    if (is.null(path) || is.na(path) || !nzchar(path)) return(FALSE)
    if (!file.exists(path)) return(FALSE)
    if (is_windows) return(TRUE)
    file.access(path, 1) == 0
  }

  tool_bin <- normalize_tool_name(tool)

  # 1) PATH (conda-first)
  p <- Sys.which(tool_bin)
  if (length(p) == 1 && nzchar(p)) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (is_executable_file(p)) return(p)
  }

  # 2) Env var override
  if (!is.null(env_var) && nzchar(env_var)) {
    pe <- Sys.getenv(env_var, unset = "")
    if (nzchar(pe)) {
      pe <- normalizePath(pe, winslash = "/", mustWork = FALSE)
      if (is_executable_file(pe)) return(pe)
    }
  }

  ""
}
