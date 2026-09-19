# inst/app/R/09_search_strategy.R

build_search_strategy <- function(input, params) {
  list(
    schema = "localignr_search_strategy_v1",
    created = as.character(Sys.time()),
    aligner = input$aligner %||% "BLAST",
    program = input$program %||% "",
    database = input$db %||% "",
    evalue = input$eval %||% "",
    preset = input$aligner_preset %||% "",
    show_advanced_params = isTRUE(input$show_advanced_params),
    parameters = params
  )
}

write_search_strategy <- function(strategy, file) {
  jsonlite::write_json(
    strategy,
    path = file,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
}

read_search_strategy <- function(path) {
  x <- jsonlite::read_json(path, simplifyVector = TRUE)
  
  if (is.null(x$schema) || !identical(x$schema, "localignr_search_strategy_v1")) {
    stop("Unsupported search strategy format.")
  }
  
  x
}