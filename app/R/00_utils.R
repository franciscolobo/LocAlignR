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
