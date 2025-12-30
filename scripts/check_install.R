#!/usr/bin/env Rscript

# scripts/check_install.R
#
# LocAlign installation smoke test.
# Run from the REPO ROOT:
#   Rscript scripts/check_install.R
#
# What it checks:
#   1) R + key R packages (optionally via renv restore)
#   2) LocAlign app folder exists and core files are present
#   3) External tools: BLAST (required) and DIAMOND (optional)
#      - Tool discovery order: env var -> PATH
#   4) Basic commands run: blastp -version, makeblastdb -version, diamond version
#
# Environment variables supported:
#   LOCALIGN_BLASTP
#   LOCALIGN_BLASTN
#   LOCALIGN_MAKEBLASTDB
#   LOCALIGN_DIAMOND (optional)
#
# Optional behavior toggles:
#   LOCALIGN_SKIP_RENV=1         Skip renv checks/restore
#   LOCALIGN_SKIP_TOOL_RUN=1     Skip running tool version commands (only checks presence)

`%||%` <- function(a, b) if (is.null(a)) b else a

cat_line <- function(...) cat(..., "\n", sep = "")

fail <- function(msg) {
  cat_line("\nERROR: ", msg)
  quit(status = 1, save = "no")
}

warn <- function(msg) {
  cat_line("WARNING: ", msg)
}

ok <- function(msg) {
  cat_line("OK: ", msg)
}

is_windows <- function() .Platform$OS.type == "windows"

normalize_tool_name <- function(tool) {
  if (is_windows() && !grepl("\\.exe$", tool, ignore.case = TRUE)) paste0(tool, ".exe") else tool
}

is_executable_file <- function(path) {
  if (is.null(path) || is.na(path) || !nzchar(path)) return(FALSE)
  if (!file.exists(path)) return(FALSE)
  if (is_windows()) return(TRUE)
  file.access(path, 1) == 0
}

find_tool <- function(tool, env_var = NULL) {
  tool_bin <- normalize_tool_name(tool)

  # 1) Environment variable
  if (!is.null(env_var) && nzchar(env_var)) {
    p <- Sys.getenv(env_var, unset = "")
    if (nzchar(p)) {
      p <- normalizePath(p, winslash = "/", mustWork = FALSE)
      if (is_executable_file(p)) return(list(path = p, via = paste0("env:", env_var)))
    }
  }

  # 2) PATH
  p <- Sys.which(tool_bin)
  if (length(p) == 1 && nzchar(p)) {
    p <- normalizePath(p, winslash = "/", mustWork = FALSE)
    if (is_executable_file(p)) return(list(path = p, via = "PATH"))
  }

  list(path = "", via = "")
}

run_cmd <- function(cmd, args = character()) {
  out <- tryCatch(
    system2(cmd, args, stdout = TRUE, stderr = TRUE),
    error = function(e) e
  )
  if (inherits(out, "error")) {
    return(list(ok = FALSE, output = out$message))
  }
  status <- attr(out, "status") %||% 0L
  list(ok = identical(status, 0L), output = paste(out, collapse = "\n"))
}

check_r_packages <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    fail(paste0(
      "Missing required R packages: ", paste(missing, collapse = ", "), "\n",
      "Run: R -e \"install.packages('renv'); renv::restore()\""
    ))
  }
  ok(paste0("All required R packages are installed (", length(pkgs), ")."))
}

# ---- Start ----

cat_line("LocAlign installation check")
cat_line("R version: ", R.version.string)
cat_line("Working directory: ", normalizePath(getwd(), winslash = "/"))

# Basic repo structure checks for Option B layout
if (!dir.exists("app")) fail("Missing 'app/' directory. Run this script from the repo root.")
if (!file.exists(file.path("app", "ui.R"))) fail("Missing app/ui.R")
if (!file.exists(file.path("app", "server.R"))) fail("Missing app/server.R")
ok("Found app/ui.R and app/server.R")

# renv (optional)
if (Sys.getenv("LOCALIGN_SKIP_RENV", unset = "0") != "1") {
  if (!file.exists("renv.lock")) {
    warn("renv.lock not found. Skipping renv restore.")
  } else {
    if (!requireNamespace("renv", quietly = TRUE)) {
      fail("Package 'renv' is not installed. Run: R -e \"install.packages('renv')\"")
    }
    cat_line("Running renv::restore(prompt = FALSE) ...")
    tryCatch(
      renv::restore(prompt = FALSE),
      error = function(e) fail(paste0("renv::restore failed: ", e$message))
    )
    ok("renv restore completed")
  }
} else {
  ok("Skipped renv checks (LOCALIGN_SKIP_RENV=1)")
}

# Minimal required R packages for your current app imports
required_pkgs <- c(
  "shiny", "shinythemes", "DT", "shinyFiles",
  "shinybusy", "XML", "plyr", "dplyr",
  "yaml", "processx", "digest", "htmltools", "htmlwidgets"
)
check_r_packages(required_pkgs)

cat_line("\nExternal tools")

# BLAST tools (required)
blastp_res <- find_tool("blastp", env_var = "LOCALIGN_BLASTP")
makeblastdb_res <- find_tool("makeblastdb", env_var = "LOCALIGN_MAKEBLASTDB")
blastn_res <- find_tool("blastn", env_var = "LOCALIGN_BLASTN") # optional for your current UI, but usually present

if (!nzchar(blastp_res$path)) fail("blastp not found (set LOCALIGN_BLASTP or install BLAST in a conda env and activate it).")
if (!nzchar(makeblastdb_res$path)) fail("makeblastdb not found (set LOCALIGN_MAKEBLASTDB or install BLAST in a conda env and activate it).")

ok(paste0("blastp: ", blastp_res$path, " (", blastp_res$via, ")"))
ok(paste0("makeblastdb: ", makeblastdb_res$path, " (", makeblastdb_res$via, ")"))

if (nzchar(blastn_res$path)) {
  ok(paste0("blastn: ", blastn_res$path, " (", blastn_res$via, ")"))
} else {
  warn("blastn not found. If you plan to run blastn/tblastn, install full BLAST+ and/or set LOCALIGN_BLASTN.")
}

# DIAMOND (optional)
diamond_res <- find_tool("diamond", env_var = "LOCALIGN_DIAMOND")
if (nzchar(diamond_res$path)) {
  ok(paste0("diamond: ", diamond_res$path, " (", diamond_res$via, ")"))
} else {
  warn("diamond not found (optional). Install it if you plan to use DIAMOND.")
}

# Optionally run tool commands
if (Sys.getenv("LOCALIGN_SKIP_TOOL_RUN", unset = "0") != "1") {
  cat_line("\nTool version checks")

  v1 <- run_cmd(blastp_res$path, c("-version"))
  if (!v1$ok) fail(paste0("Failed to run blastp -version: ", v1$output))
  cat_line("blastp -version:\n", v1$output, "\n")

  v2 <- run_cmd(makeblastdb_res$path, c("-version"))
  if (!v2$ok) fail(paste0("Failed to run makeblastdb -version: ", v2$output))
  cat_line("makeblastdb -version:\n", v2$output, "\n")

  if (nzchar(diamond_res$path)) {
    v3 <- run_cmd(diamond_res$path, c("version"))
    if (!v3$ok) fail(paste0("Failed to run diamond version: ", v3$output))
    cat_line("diamond version:\n", v3$output, "\n")
  }
} else {
  ok("Skipped running tool commands (LOCALIGN_SKIP_TOOL_RUN=1)")
}

cat_line("\nAll checks passed.")
quit(status = 0, save = "no")

