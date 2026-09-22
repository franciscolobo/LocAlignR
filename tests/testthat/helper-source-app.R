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

# =============================================================================
# CRITICAL SAFETY GUARD -- READ BEFORE MODIFYING THIS FILE
#
# 02_user_db_registry.R and 11_user_preferences.R each compute a REAL,
# machine-specific config file path at source time:
#   user_db_file          <- file.path(tools::R_user_dir(...), "user_dbs.yml")
#   user_preferences_file <- file.path(tools::R_user_dir(...), "user_preferences.yml")
#
# save_user_dbs()/save_user_preferences() default to writing to THESE exact
# bindings (as `path = user_db_file` etc in their signatures). Because these
# are plain global functions (not package-namespaced), R resolves that
# default argument by looking up the CURRENT value of user_db_file in
# globalenv() at call time -- not at definition time.
#
# This previously caused real data loss: a test exercising
# wire_databases()'s removal handler overwrote a real user's actual
# user_dbs.yml with test fixture data, because a
# testthat::local_mocked_bindings() guard on save_user_dbs() did not
# actually intercept the call (that mechanism is designed for
# package-namespaced functions; save_user_dbs() here is a loose function
# sourced into globalenv(), so the mock silently no-opped).
#
# Fix: immediately after sourcing, forcibly rebind user_db_file and
# user_preferences_file in globalenv() to per-test-session temp paths, and
# assert neither one resolves to a real user config location. This makes it
# structurally impossible for any test in this suite to touch a real
# user's config files, regardless of whether a given test remembers to add
# its own mock.
# =============================================================================

.test_session_config_dir <- tempfile("localignr_global_test_config_")
dir.create(.test_session_config_dir, recursive = TRUE)

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

# Checked against known real per-OS LocAlignR config locations, including
# the macOS path confirmed in this project's actual incident:
# ~/Library/Preferences/org.R-project.R/R/LocAlignR/user_dbs.yml
.looks_like_real_user_config_path <- function(path) {
  grepl("Library/Preferences/org\\.R-project\\.R", path) ||
    grepl("\\.config/R/LocAlignR", path) ||
    grepl("AppData.*LocAlignR", path)
}

.rebind_config_paths_to_safe_temp <- function(dir) {
  assign("user_db_file", file.path(dir, "user_dbs.yml"), envir = globalenv())
  assign("user_preferences_file", file.path(dir, "user_preferences.yml"), envir = globalenv())
}

.assert_config_paths_are_safe <- function(context = "") {
  udb <- get("user_db_file", envir = globalenv(), inherits = FALSE)
  upr <- get("user_preferences_file", envir = globalenv(), inherits = FALSE)

  if (.looks_like_real_user_config_path(udb) || .looks_like_real_user_config_path(upr)) {
    stop(
      "SAFETY ABORT", if (nzchar(context)) paste0(" (", context, ")"), ": ",
      "test config paths resolved to what looks like a real user config ",
      "directory. Refusing to continue rather than risk overwriting real ",
      "user data. user_db_file = ", udb, ", user_preferences_file = ", upr
    )
  }
}

.rebind_config_paths_to_safe_temp(.test_session_config_dir)
.assert_config_paths_are_safe("initial helper setup")

# Note: .test_session_config_dir is intentionally left for the OS temp
# cleanup rather than removed explicitly -- these are tiny YAML files and
# adding a suite-teardown hook here would require a new dependency (e.g.
# withr) not currently declared anywhere in this project.

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
# confirmed empirically in this codebase via debug logging.
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
#' @return A list with `fn` (the fake function to inject) and `calls_env`
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
# Infrastructure for testing the REAL server() function from server.R,
# rather than a re-implementation. Deliberately scoped to a couple of
# observers known to be bug-prone this session -- not exhaustive coverage
# of server() -- since full coverage would re-test logic already covered by
# wire_diagnostics/wire_databases tests and the pure-logic suite.
#
# server.R has three environment dependencies that must be sandboxed:
#   1. Working directory: server.R does setwd-relative source()/read calls.
#   2/3. tools::R_user_dir() (config + cache): backs user_db_file,
#      user_preferences_file, and localignr_log_dir().
#
# IMPORTANT SCOPING NOTE: server.R's own internal source(...) calls (e.g.
# source("R/02_user_db_registry.R")) do NOT pass local = TRUE, so base R's
# source() defaults to sourcing into globalenv() -- regardless of the
# `envir` this file itself is sys.source()'d into. This means sourcing
# server.R here does NOT create an isolated copy of user_db_file inside
# server_env; it (re-)defines user_db_file in globalenv(), same as
# .source_app_file() above does. This function accounts for that explicitly
# by re-asserting and re-rebinding safe paths in globalenv() AFTER
# sys.source() runs, rather than assuming isolation that sys.source()'s
# envir argument does not actually provide for nested source() calls.
# =============================================================================

with_sandboxed_server <- function(code, seed_config_yml = NULL) {
  app_root <- normalizePath(file.path(.app_r_dir, ".."), winslash = "/", mustWork = TRUE)

  old_wd <- getwd()
  old_config_dir <- Sys.getenv("R_USER_CONFIG_DIR", unset = NA)
  old_cache_dir  <- Sys.getenv("R_USER_CACHE_DIR", unset = NA)

  # Preserve whatever globalenv() config paths were in place before this
  # call (set by the helper setup above, or by a previous
  # with_sandboxed_server() call), so they can be restored afterward.
  old_global_user_db_file <- get("user_db_file", envir = globalenv(), inherits = FALSE)
  old_global_user_prefs_file <- get("user_preferences_file", envir = globalenv(), inherits = FALSE)

  tmp_config <- tempfile("localignr_test_config_")
  tmp_cache  <- tempfile("localignr_test_cache_")
  dir.create(tmp_config, recursive = TRUE)
  dir.create(tmp_cache, recursive = TRUE)

  Sys.setenv(R_USER_CONFIG_DIR = tmp_config, R_USER_CACHE_DIR = tmp_cache)
  setwd(app_root)

  config_yml_path <- file.path(app_root, "config.yml")
  wrote_config_yml <- FALSE

  if (!is.null(seed_config_yml)) {
    yaml::write_yaml(seed_config_yml, config_yml_path)
    wrote_config_yml <- TRUE
  }

  on.exit({
    setwd(old_wd)
    if (is.na(old_config_dir)) Sys.unsetenv("R_USER_CONFIG_DIR") else Sys.setenv(R_USER_CONFIG_DIR = old_config_dir)
    if (is.na(old_cache_dir)) Sys.unsetenv("R_USER_CACHE_DIR") else Sys.setenv(R_USER_CACHE_DIR = old_cache_dir)
    unlink(tmp_config, recursive = TRUE)
    unlink(tmp_cache, recursive = TRUE)
    if (wrote_config_yml) unlink(config_yml_path)
    # Restore globalenv()'s config paths to whatever they were before this
    # call, so a later test file isn't left depending on this call's temp
    # dir (which is about to be deleted, above).
    assign("user_db_file", old_global_user_db_file, envir = globalenv())
    assign("user_preferences_file", old_global_user_prefs_file, envir = globalenv())
  }, add = TRUE)

  server_env <- new.env(parent = globalenv())

  capture <- make_capturing_update_select_input()
  server_env$updateSelectInput <- capture$fn

  sys.source(file.path(app_root, "server.R"), envir = server_env)

  # server.R's internal source("R/02_user_db_registry.R") (no local = TRUE)
  # just re-defined user_db_file/user_preferences_file in globalenv() --
  # see the scoping note above. Force them back to this call's safe temp
  # dir regardless of what that re-sourcing computed, and verify.
  .rebind_config_paths_to_safe_temp(tmp_config)
  .assert_config_paths_are_safe("with_sandboxed_server, after sys.source")

  server_fn <- server_env$server
  attr(server_fn, "update_select_calls") <- capture$calls_env

  force(code(server_fn))
}
