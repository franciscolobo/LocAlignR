# inst/app/R/08_aligner_params.R

default_thread_count <- function() {
  as.integer(max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
}

preset_choices <- function(aligner) {
  
  aligner <- toupper(aligner)
  
  names(
    aligner_presets()[[aligner]]
  )
}

get_preset_values <- function(aligner, preset) {
  
  aligner <- toupper(aligner)
  
  aligner_presets()[[aligner]][[preset]]
}

aligner_presets <- function() {
  
  list(
    
    BLAST = list(
      
      Fast = list(
        max_target_seqs = 10L,
        max_hsps = 1L
      ),
      
      Default = list(
        max_target_seqs = 10L,
        max_hsps = 1L
      ),
      
      Sensitive = list(
        max_target_seqs = 50L,
        max_hsps = 5L
      )
    ),
    
    DIAMOND = list(
      
      Fast = list(
        max_target_seqs = 10L,
        sensitivity = "default"
      ),
      
      Default = list(
        max_target_seqs = 10L,
        sensitivity = "sensitive"
      ),
      
      Sensitive = list(
        max_target_seqs = 50L,
        sensitivity = "very-sensitive"
      ),
      
      `Ultra-sensitive` = list(
        max_target_seqs = 100L,
        sensitivity = "ultra-sensitive"
      )
    )
  )
}

aligner_parameter_spec <- function() {
  list(
    BLAST = list(
      
      max_target_seqs = list(
        label = "Max target sequences",
        input = "numeric",
        default = 10L,
        min = 1L,
        step = 1L,
        level = "basic"
      ),
      
      max_hsps = list(
        label = "Max HSPs",
        input = "numeric",
        default = 1L,
        min = 1L,
        step = 1L,
        level = "advanced"
      ),
      
      culling_limit = list(
        label = "Culling limit",
        input = "numeric_optional",
        default = NULL,
        min = 0L,
        step = 1L,
        level = "advanced",
        help = "Suppress lower-scoring hits whose query range is enveloped by higher-scoring hits. Leave blank to disable."
      ),
      
      best_hit_overhang = list(
        label = "Best-hit overhang",
        input = "numeric_decimal",
        default = NULL,
        level = "advanced",
        help = "BLAST best-hit filtering overhang. Requires best-hit score edge."
      ),
      
      best_hit_score_edge = list(
        label = "Best-hit score edge",
        input = "numeric_decimal",
        default = NULL,
        level = "advanced",
        help = "BLAST best-hit filtering score edge. Requires best-hit overhang."
      ),
      
      word_size = list(
        label = "Word size",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastn", "tblastx"),
        level = "advanced"
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
        ),
        level = "advanced"
      ),
      
      gapopen = list(
        label = "Gap open penalty",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastp", "blastx", "tblastn"),
        level = "advanced"
      ),
      
      gapextend = list(
        label = "Gap extension penalty",
        input = "numeric_optional",
        default = NULL,
        programs = c("blastp", "blastx", "tblastn"),
        level = "advanced"
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
        step = 1L
      ),
      
      sensitivity = list(
        label = "Sensitivity",
        input = "select",
        default = "default",
        choices = c(
          "Default" = "default",
          "Sensitive" = "sensitive",
          "More sensitive" = "more-sensitive",
          "Very sensitive" = "very-sensitive",
          "Ultra sensitive" = "ultra-sensitive"
        ),
        level = "advanced"
      ),
      
      top = list(
        label = "Top (%)",
        input = "numeric_optional",
        default = NULL,
        level = "advanced"
      ),
      
      block_size = list(
        label = "Block size (billions of letters)",
        input = "numeric_decimal",
        default = NULL,
        level = "advanced"
      ),
      
      index_chunks = list(
        label = "Index chunks",
        input = "numeric_optional",
        default = NULL,
        level = "advanced"
      ),
      
      threads = list(
        label = "Threads",
        input = "numeric",
        default = default_thread_count(),
        min = 1L,
        step = 1L
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

render_aligner_parameter_inputs <- function(
    aligner,
    program = NULL,
    show_advanced = FALSE,
    values = list()
) {
  defs <- get_aligner_parameter_defs(aligner, program)
  
  if (!length(defs)) {
    return(NULL)
  }
  
  if (!isTRUE(show_advanced)) {
    keep <- vapply(
      defs,
      function(def) {
        identical(def$level %||% "basic", "basic")
      },
      logical(1)
    )
    
    defs <- defs[keep]
  }
  
  if (!length(defs)) {
    return(NULL)
  }
  
  widgets <- lapply(names(defs), function(param_name) {
    def <- defs[[param_name]]
    id <- aligner_param_input_id(param_name)
    value <- values[[param_name]] %||% def$default
    
    widget <- switch(
      def$input,
      
      numeric = numericInput(
        inputId = id,
        label = def$label,
        value = value,
        min = def$min %||% NA,
        max = def$max %||% NA,
        step = def$step %||% NA
      ),
      
      numeric_optional = textInput(
        inputId = id,
        label = def$label,
        value = if (is.null(value)) "" else as.character(value),
        placeholder = def$placeholder %||% "Use program default"
      ),
      
      numeric_decimal = textInput(
        inputId = id,
        label = def$label,
        value = if (is.null(value)) "" else as.character(value),
        placeholder = def$placeholder %||% "Use program default"
      ),
      
      select = selectInput(
        inputId = id,
        label = def$label,
        choices = def$choices,
        selected = value
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
    tags$h5(if (isTRUE(show_advanced)) "Parameters" else "Basic parameters"),
    widgets
  )
}

coerce_aligner_param_value <- function(raw_value, def) {
  if (identical(def$input, "numeric")) {
    if (is.null(raw_value) || length(raw_value) == 0 || is.na(raw_value)) {
      return(def$default)
    }
    
    value <- suppressWarnings(as.integer(raw_value))
    
    if (!is.finite(value)) {
      return(def$default)
    }
    
    return(value)
  }
  
  if (identical(def$input, "numeric_optional")) {
    if (is.null(raw_value) || length(raw_value) == 0) {
      return(NULL)
    }
    
    txt <- trimws(as.character(raw_value %||% ""))
    
    if (!nzchar(txt)) {
      return(NULL)
    }
    
    value <- suppressWarnings(as.integer(txt))
    
    if (!is.finite(value)) {
      return(NULL)
    }
    
    return(value)
  }
  
  if (identical(def$input, "numeric_decimal")) {
    if (is.null(raw_value) || length(raw_value) == 0) {
      return(NULL)
    }
    
    txt <- trimws(as.character(raw_value %||% ""))
    
    if (!nzchar(txt)) {
      return(NULL)
    }
    
    value <- suppressWarnings(as.numeric(txt))
    
    if (!is.finite(value)) {
      return(NULL)
    }
    
    return(value)
  }
  
  if (identical(def$input, "select")) {
    if (
      is.null(raw_value) ||
      length(raw_value) == 0 ||
      is.na(raw_value) ||
      !nzchar(trimws(as.character(raw_value)))
    ) {
      return(def$default)
    }
    
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
