# testthat auto-sources every helper-*.R file in tests/testthat/ before
# running tests. This one locates and sources the aligner-agnostic,
# pure-logic files from inst/app/R/ (the app itself isn't part of the
# package namespace, so these must be sourced directly, same as server.R
# does at runtime).
#
# Deliberately NOT sourced here: 05_blast_run.R, 06_diamond_run.R,
# 07_makeseqdb.R (all three shell out to external BLAST+/DIAMOND binaries --
# testing those is an integration-test concern, not a unit-test one), and
# 90_diagnostics.R / 91_databases.R (Shiny-reactive wiring, not pure logic).
# =============================================================================

library(shiny)
library(dplyr)

.locate_app_r_dir <- function() {
  installed <- system.file("app", "R", package = "LocAlignR")
  if (nzchar(installed) && dir.exists(installed)) return(installed)

  candidates <- c(
    "inst/app/R",
    "../../inst/app/R",
    file.path(testthat::test_path(), "..", "..", "inst", "app", "R")
  )

  for (cand in candidates) {
    if (dir.exists(cand)) return(normalizePath(cand, winslash = "/", mustWork = FALSE))
  }

  stop(
    "Could not locate inst/app/R. Run tests via devtools::test() or ",
    "R CMD check from the package root."
  )
}

.app_r_dir <- .locate_app_r_dir()

.source_app_file <- function(fname) {
  source(file.path(.app_r_dir, fname), local = FALSE)
}

# Order matters: later files assume %||% (00) and canon_id (01) already exist.
for (f in c(
  "00_utils.R",
  "01_metadata.R",
  "02_user_db_registry.R",
  "03_alignment_rendering.R",
  "04_alignment_results.R",
  "08_aligner_dispatch.R",
  "09_aligner_params.R",
  "10_search_strategy.R",
  "11_user_preferences.R"
)) {
  .source_app_file(f)
}

# shiny::validate()/need() throw a classed condition rather than a normal
# error. This helper lets tests assert on validation failures without
# needing an active Shiny reactive context.
expect_shiny_validation_error <- function(expr, regexp = NULL) {
  cond <- tryCatch(
    { force(expr); NULL },
    shiny.silent.error = function(e) e,
    error = function(e) e
  )

  testthat::expect_false(
    is.null(cond),
    info = "Expected a shiny::validate() failure, but the expression succeeded."
  )

  if (!is.null(regexp)) {
    testthat::expect_match(conditionMessage(cond), regexp)
  }
}

