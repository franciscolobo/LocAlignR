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
for (.f in c(
  "00_utils.R",
  "01_metadata.R",
  "02_user_db_registry.R",
  "03_alignment_rendering.R",
  "04_alignment_results.R",
  "08_aligner_dispatch.R",
  "09_aligner_params.R",
  "10_search_strategy.R",
  "11_user_preferences.R",
  "90_diagnostics.R",
  "91_databases.R"
)) {
  .source_app_file(.f)
}
rm(.f)

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

# =============================================================================
# NOTE ON shiny::testServer() AND update*Input() FUNCTIONS
#
# testServer() runs server-side reactive code against a mock session, but it
# does NOT simulate a real browser. In a real app, updateSelectInput() etc.
# work by sending a message to the browser's JS, which the browser then
# echoes back as a new value on input$x. testServer() has no browser to do
# that echoing -- so update*Input() calls execute successfully inside a
# test, but input$x is never actually updated afterward, no matter how many
# times session$flushReact() is called. This is documented shiny behavior,
# not a bug in the app.
#
# Confirmed empirically in this codebase: debug logging showed
# wire_databases()'s removal observer and server.R's aligner-sync observer
# both computed the correct new selection and called updateSelectInput()
# with it, yet input$db / input$program remained unchanged afterward.
#
# The correct way to test this class of behavior is to intercept the
# update*Input() calls themselves and assert on what they were called
# with, rather than asserting on input$x afterward. Both wire_databases()
# and server()'s observers call updateSelectInput(...) UNQUALIFIED (no
# shiny:: prefix), which resolves via R's lexical scoping to whatever
# environment the calling function was DEFINED in. By pre-assigning a
# capturing fake updateSelectInput() directly into that same environment
# BEFORE sourcing the real code, unqualified calls inside it find the fake
# version first -- no changes to server.R or 91_databases.R required.
# =============================================================================

#' Create a fake updateSelectInput() that records every call instead of
#' sending a (no-op, in tests) message to a browser.
#'
#' @return A list with `fn` (the fake function to inject) and `calls`
#'   (an environment holding an accumulating list of call records).
make_capturing_update_select_input <- function() {
  store <- new.env(parent = emptyenv())
  store$calls <- list()

  fn <- function(session, inputId, choices = NULL, selected = NULL, ...) {
    store$calls[[length(store$calls) + 1]] <- list(
      inputId = inputId, choices = choices, selected = selected
    )
    invisible(NULL)
  }

  list(fn = fn, calls_env = store)
}

#' Most recent captured updateSelectInput() call for a given inputId, or
#' NULL if that input was never updated.
last_update_for <- function(calls_env, input_id) {
  matching <- Filter(function(x) identical(x$inputId, input_id), calls_env$calls)
  if (!length(matching)) return(NULL)
  matching[[length(matching)]]
}

# =============================================================================
# with_sandboxed_server(): as before (temp config/cache dirs, setwd), PLUS
# now injects the capturing updateSelectInput() fake into server_env before
# sourcing server.R, and attaches the calls environment as an attribute on
# the returned server function so tests can inspect it.
# =============================================================================
with_sandboxed_server <- function(code, empty_seed_registry = FALSE) {
  app_root <- normalizePath(file.path(.app_r_dir, ".."), winslash = "/", mustWork = TRUE)

  old_wd <- getwd()
  old_config_dir <- Sys.getenv("R_USER_CONFIG_DIR", unset = NA)
  old_cache_dir  <- Sys.getenv("R_USER_CACHE_DIR", unset = NA)

  tmp_config <- tempfile("localignr_test_config_")
  tmp_cache  <- tempfile("localignr_test_cache_")
  dir.create(tmp_config, recursive = TRUE)
  dir.create(tmp_cache, recursive = TRUE)

  Sys.setenv(R_USER_CONFIG_DIR = tmp_config, R_USER_CACHE_DIR = tmp_cache)
  setwd(app_root)

  on.exit({
    setwd(old_wd)
    if (is.na(old_config_dir)) Sys.unsetenv("R_USER_CONFIG_DIR") else Sys.setenv(R_USER_CONFIG_DIR = old_config_dir)
    if (is.na(old_cache_dir)) Sys.unsetenv("R_USER_CACHE_DIR") else Sys.setenv(R_USER_CACHE_DIR = old_cache_dir)
    unlink(tmp_config, recursive = TRUE)
    unlink(tmp_cache, recursive = TRUE)
  }, add = TRUE)

  server_env <- new.env(parent = globalenv())

  capture <- make_capturing_update_select_input()
  server_env$updateSelectInput <- capture$fn

  if (isTRUE(empty_seed_registry)) {
    # load_or_default_config("config.yml") falls back to hardcoded,
    # developer-machine-specific default databases (Mlig_core_nt /
    # Mlig_core_aa, defined in 02_user_db_registry.R) whenever config.yml
    # is absent -- which it always is in this sandboxed working directory.
    # Some tests need a genuinely empty registry to test fallback behavior
    # (e.g. falling back to the remote "nt"/"nr" shortcuts). Injecting this
    # override BEFORE sourcing server.R uses the same lexical-scoping trick
    # as updateSelectInput above: server()'s unqualified call to
    # load_or_default_config() resolves to this version instead of the
    # real one sourced from 02_user_db_registry.R moments later.
    server_env$load_or_default_config <- function(cfg_file = "config.yml") {
      list(databases = list())
    }
  }

  sys.source(file.path(app_root, "server.R"), envir = server_env)

  server_fn <- server_env$server
  attr(server_fn, "update_select_calls") <- capture$calls_env

  force(code(server_fn))
}
