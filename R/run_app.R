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

  # Fallback for devtools::load_all(): use inst/app from the source tree
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    app_dir <- file.path(getwd(), "inst", "app")
  }

  if (!dir.exists(app_dir)) {
    stop(
      "LocAlign app directory not found. Expected 'inst/app' at the package root.",
      call. = FALSE
    )
  }

  shiny::runApp(app_dir, launch.browser = launch.browser, ...)
}
