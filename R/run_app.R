# R/run_app.R

#' Run the LocAlign Shiny app
#'
#' @param launch.browser Logical. If TRUE, open the app in a browser.
#' @param ... Passed to shiny::runApp().
#' @return None. Starts a Shiny app.
#' @export
run_app <- function(launch.browser = TRUE, ...) {
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("Missing dependency: shiny", call. = FALSE)
  }

  # Prefer installed location (R CMD INSTALL / conda-installed package)
  app_dir <- system.file("app", package = "LocAlign")

  # Fallback for devtools::load_all(): try to locate the package source tree
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    dev_root <- NULL

    # pkgload knows where the source tree is during devtools::load_all()
    if (requireNamespace("pkgload", quietly = TRUE)) {
      dev_root <- tryCatch(pkgload::pkg_path("LocAlign"), error = function(e) NULL)
    }

    # Last resort: assume current working directory is the repo root
    if (is.null(dev_root) || !nzchar(dev_root)) {
      dev_root <- getwd()
    }

    app_dir <- file.path(dev_root, "inst", "app")
  }

  if (!dir.exists(app_dir)) {
    stop(
      "LocAlign app directory not found. Expected 'inst/app' at the package root.",
      call. = FALSE
    )
  }

  # In non-interactive sessions (e.g. double-click launcher), be explicit about how to open the browser.
  if (isTRUE(launch.browser) && !interactive()) {
    launch.browser <- function(url) {
      sysname <- Sys.info()[["sysname"]]
      if (identical(sysname, "Darwin")) {
        system2("open", c(url), wait = FALSE)
      } else if (identical(.Platform$OS.type, "windows")) {
        shell.exec(url)
      } else {
        system2("xdg-open", c(url), wait = FALSE)
      }
    }
  }
  shiny::runApp(app_dir, launch.browser = launch.browser, ...)
}
