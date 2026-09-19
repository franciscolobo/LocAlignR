# inst/app/R/10_user_preferences.R

user_preferences_file <- file.path(
  tools::R_user_dir("LocAlignR", which = "config"),
  "user_preferences.yml"
)

ensure_user_preferences_dir <- function() {
  dir.create(dirname(user_preferences_file), recursive = TRUE, showWarnings = FALSE)
}

load_user_preferences <- function(path = user_preferences_file) {
  if (!file.exists(path)) {
    return(list())
  }

  x <- tryCatch(yaml::read_yaml(path), error = function(e) list())
  if (is.null(x)) list() else x
}

save_user_preferences <- function(prefs, path = user_preferences_file) {
  ensure_user_preferences_dir()

  tmp <- paste0(path, ".tmp")
  yaml::write_yaml(prefs, tmp)
  file.rename(tmp, path)

  invisible(NULL)
}

build_current_preferences <- function(input, params = list()) {
  list(
    aligner = input$aligner %||% "BLAST",
    program = input$program %||% "",
    database = input$db %||% "",
    evalue = input$eval %||% "1e-5",
    preset = input$aligner_preset %||% "",
    show_advanced_params = isTRUE(input$show_advanced_params),
    parameters = params
  )
}
