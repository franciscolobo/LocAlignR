# inst/app/R/08_aligner_params.R

default_thread_count <- function() {
  as.integer(max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
}

aligner_parameter_spec <- function() {
  list(
    BLAST = list(
      
      max_target_seqs = list(
        label = "Max target sequences",
        input = "numeric",
        default = 10L,
        min = 1L,
        step = 1L
      ),
      
      max_hsps = list(
        label = "Max HSPs",
        input = "numeric",
        default = 1L,
        min = 1L,
        step = 1L
      ),
      
      word_size = list(
        label = "Word size",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastn", "tblastx")
      ),
      
      matrix = list(
        label = "Scoring matrix",
        input = "select",
        default = "BLOSUM62",
        programs = c("blastp", "blastx", "tblastn"),
        choices = c(
          "BLOSUM45",
          "BLOSUM62",
          "BLOSUM80",
          "PAM250"
        )
      ),
      
      gapopen = list(
        label = "Gap open penalty",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastp", "blastx", "tblastn")
      ),
      
      gapextend = list(
        label = "Gap extension penalty",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastp", "blastx", "tblastn")
      ),
      
      threads = list(
        label = "Threads",
        input = "numeric",
        default = default_thread_count(),
        min = 1L,
        step = 1L
      )
    ),
    
    DIAMOND = list(
      max_target_seqs = list(
        label = "Max target sequences",
        input = "numeric",
        default = 10L,
        min = 1L,
        step = 1L,
        help = "Maximum number of target sequences reported."
      ),
      threads = list(
        label = "Threads",
        input = "numeric",
        default = default_thread_count(),
        min = 1L,
        step = 1L,
        help = "Number of CPU threads to use."
      )
    )
  )
}

get_aligner_parameter_defs <- function(aligner, program = NULL) {
  aligner <- toupper(aligner %||% "BLAST")
  defs <- aligner_parameter_spec()[[aligner]]
  
  if (is.null(defs)) {
    return(list())
  }
  
  keep <- vapply(defs, function(def) {
    progs <- def$programs %||% NULL
    
    if (is.null(progs)) {
      TRUE
    } else {
      !is.null(program) && program %in% progs
    }
  }, logical(1))
  
  defs[keep]
}

aligner_param_input_id <- function(param_name) {
  paste0("aligner_param__", param_name)
}

render_aligner_parameter_inputs <- function(aligner, program = NULL) {
  defs <- get_aligner_parameter_defs(aligner, program)
  
  if (!length(defs)) {
    return(NULL)
  }
  
  widgets <- lapply(names(defs), function(param_name) {
    def <- defs[[param_name]]
    id <- aligner_param_input_id(param_name)
    
    widget <- switch(
      def$input,
      
      numeric = numericInput(
        inputId = id,
        label = def$label,
        value = def$default,
        min = def$min %||% NA,
        max = def$max %||% NA,
        step = def$step %||% NA
      ),
      
      numeric_optional = textInput(
        inputId = id,
        label = def$label,
        value = if (is.null(def$default)) "" else as.character(def$default),
        placeholder = "Use program default"
      ),
      
      select = selectInput(
        inputId = id,
        label = def$label,
        choices = def$choices,
        selected = def$default
      ),
      
      stop("Unsupported parameter input type: ", def$input)
    )
    
    tagList(
      widget,
      if (nzchar(def$help %||% "")) {
        tags$small(class = "text-muted", def$help)
      }
    )
  })
  
  tagList(
    tags$hr(),
    tags$h5("Advanced parameters"),
    widgets
  )
}

coerce_aligner_param_value <- function(raw_value, def) {
  if (identical(def$input, "numeric")) {
    if (is.null(raw_value) || is.na(raw_value)) {
      return(def$default)
    }
    return(as.integer(raw_value))
  }
  
  if (identical(def$input, "numeric_optional")) {
    txt <- trimws(as.character(raw_value %||% ""))
    
    if (!nzchar(txt)) {
      return(NULL)
    }
    
    return(as.integer(txt))
  }
  
  if (identical(def$input, "select")) {
    return(as.character(raw_value))
  }
  
  raw_value
}

collect_aligner_params <- function(input, aligner, program = NULL) {
  defs <- get_aligner_parameter_defs(aligner, program)
  
  if (!length(defs)) {
    return(list())
  }
  
  out <- lapply(names(defs), function(param_name) {
    id <- aligner_param_input_id(param_name)
    raw_value <- input[[id]]
    coerce_aligner_param_value(raw_value, defs[[param_name]])
  })
  
  names(out) <- names(defs)
  out
}
