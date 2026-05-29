ALIGNER_PARAMETERS <- list(

  BLAST = list(

    max_target_seqs = list(
      type = "integer",
      default = 10,
      label = "Maximum hits"
    ),

    max_hsps = list(
      type = "integer",
      default = 1,
      label = "Maximum HSPs"
    ),

    word_size = list(
      type = "integer",
      default = NULL,
      label = "Word size"
    ),

    gapopen = list(
      type = "integer",
      default = NULL,
      label = "Gap open penalty"
    ),

    gapextend = list(
      type = "integer",
      default = NULL,
      label = "Gap extension penalty"
    ),

    threads = list(
      type = "integer",
      default = 4,
      label = "Threads"
    )
  ),

  DIAMOND = list(

    max_target_seqs = list(
      type = "integer",
      default = 10,
      label = "Maximum hits"
    ),

    sensitivity = list(
      type = "choice",
      choices = c(
        "default",
        "sensitive",
        "more-sensitive",
        "very-sensitive",
        "ultra-sensitive"
      ),
      default = "default"
    ),

    block_size = list(
      type = "numeric",
      default = 2.0
    ),

    index_chunks = list(
      type = "integer",
      default = 4
    ),

    threads = list(
      type = "integer",
      default = 4
    )
  )
)
