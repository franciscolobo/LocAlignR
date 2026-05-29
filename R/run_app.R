# R/run_app.R

#' Run the LocAlignR Shiny app
#'
#' @param launch.browser Logical. If TRUE, open the app in a browser.
#' @param ... Passed to shiny::runApp().
#' @return None. Starts a Shiny app.
#' @export
run_app <- function(launch.browser = TRUE, ...) {
  log_dir <- path.expand("~/Library/Logs/LocAlignR")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  log_file <- file.path(log_dir, "app_startup.log")

  log_line <- function(...) {
    msg <- paste0(...)
    cat(
      sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg),
      file = log_file,
      append = TRUE
    )
  }

  cat(
    "\n============================================================\n",
    file = log_file,
    append = TRUE
  )
  log_line("Starting LocAlignR::run_app()")
  log_line("R version: ", R.version.string)
  log_line("Platform: ", R.version$platform)
  log_line("Working directory: ", getwd())
  log_line(".libPaths(): ", paste(.libPaths(), collapse = " | "))

  env_vars <- c(
    "PATH",
    "CONDA_PREFIX",
    "CONDA_DEFAULT_ENV",
    "R_HOME",
    "DYLD_LIBRARY_PATH",
    "LD_LIBRARY_PATH"
  )
  for (nm in env_vars) {
    val <- Sys.getenv(nm, unset = "")
    log_line("ENV ", nm, "=", if (nzchar(val)) val else "<unset>")
  }

  startup_pkgs <- c(
    "Rcpp",
    "later",
    "promises",
    "httpuv",
    "jsonlite",
    "htmltools",
    "rlang",
    "shiny"
  )

  for (pkg in startup_pkgs) {
    log_line("Loading package: ", pkg)

    ok <- tryCatch({
      suppressPackageStartupMessages(
        library(pkg, character.only = TRUE)
      )
      TRUE
    }, error = function(e) {
      log_line("ERROR while loading ", pkg, ": ", conditionMessage(e))
      FALSE
    })

    if (!ok) {
      stop(
        sprintf(
          "Failed while loading package '%s'. See %s",
          pkg, log_file
        ),
        call. = FALSE
      )
    }

    log_line("Loaded package successfully: ", pkg)
  }

  log_line("sessionInfo() begin")
  si <- capture.output(utils::sessionInfo())
  cat(paste0(si, collapse = "\n"), "\n", file = log_file, append = TRUE)
  log_line("sessionInfo() end")

  # Prefer installed location (R CMD INSTALL / conda-installed package)
  app_dir <- system.file("app", package = "LocAlignR")
  log_line("Installed app_dir candidate: ", if (nzchar(app_dir)) app_dir else "<empty>")

  # Fallback for devtools::load_all(): try to locate the package source tree
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    log_line("Installed app directory not found; trying development fallbacks")
    dev_root <- NULL

    if (requireNamespace("pkgload", quietly = TRUE)) {
      log_line("Trying pkgload::pkg_path('LocAlignR')")
      dev_root <- tryCatch(
        pkgload::pkg_path("LocAlignR"),
        error = function(e) {
          log_line("pkgload::pkg_path failed: ", conditionMessage(e))
          NULL
        }
      )
    } else {
      log_line("pkgload not available")
    }

    if (is.null(dev_root) || !nzchar(dev_root)) {
      dev_root <- getwd()
      log_line("Using getwd() as development root fallback: ", dev_root)
    }

    app_dir <- file.path(dev_root, "inst", "app")
    log_line("Development app_dir candidate: ", app_dir)
  }

  if (!dir.exists(app_dir)) {
    log_line("ERROR: App directory not found: ", app_dir)
    stop(
      sprintf(
        "LocAlignR app directory not found. Expected 'inst/app' at the package root. See %s",
        log_file
      ),
      call. = FALSE
    )
  }

  log_line("Resolved app_dir: ", app_dir)

  if (isTRUE(launch.browser) && !interactive()) {
    log_line("Non-interactive session detected; using explicit browser launcher")
    launch.browser <- function(url) {
      log_line("Browser launch requested for URL: ", url)
      sysname <- Sys.info()[["sysname"]]

      if (identical(sysname, "Darwin")) {
        log_line("Launching browser with macOS 'open'")
        system2("open", c(url), wait = FALSE)
      } else if (identical(.Platform$OS.type, "windows")) {
        log_line("Launching browser with shell.exec")
        shell.exec(url)
      } else {
        log_line("Launching browser with xdg-open")
        system2("xdg-open", c(url), wait = FALSE)
      }
    }
  }

  options(shiny.maxRequestSize = 1024^3)
  log_line("Set shiny.maxRequestSize to 1 GiB")
  log_line("Calling shiny::runApp()")

  tryCatch(
    shiny::runApp(app_dir, launch.browser = launch.browser, ...),
    error = function(e) {
      log_line("ERROR from shiny::runApp(): ", conditionMessage(e))
      stop(e)
    }
  )
}
