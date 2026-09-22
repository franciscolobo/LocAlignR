build_job_report <- function(
    input,
    registry_entry,
    results_df,
    params
) {
  
  n_hits <- nrow(results_df)
  
  # Previously read results_df$subject_id / $bit_score / $evalue, which do
  # not exist -- the real columns from parse_blast_xml_to_df() are hit_ID,
  # bitscore, and eval. `$` on a missing column silently returns NULL
  # rather than erroring, so this always produced an empty/malformed
  # top-hit summary regardless of how many real hits were found.
  #
  # Also select the actual highest-bitscore row rather than assuming
  # row 1 is already the best hit -- BLAST/DIAMOND XML output is typically
  # sorted that way today, but nothing here enforced it, so a future
  # upstream change could silently make "top hit" wrong without this
  # function ever knowing.
  top_idx <- if (n_hits > 0) {
    bitscores <- suppressWarnings(as.numeric(results_df$bitscore))
    if (all(is.na(bitscores))) 1L else which.max(bitscores)
  } else {
    NA_integer_
  }
  
  top_hit <- if (n_hits > 0) {
    as.character(results_df$hit_ID[top_idx])
  } else {
    NA_character_
  }
  
  top_bitscore <- if (n_hits > 0) {
    suppressWarnings(as.numeric(results_df$bitscore[top_idx]))
  } else {
    NA_real_
  }
  
  top_evalue <- if (n_hits > 0) {
    suppressWarnings(as.numeric(results_df$eval[top_idx]))
  } else {
    NA_real_
  }
  
  list(
    generated = as.character(Sys.time()),
    
    search = list(
      aligner = input$aligner,
      program = input$program,
      database = input$db,
      evalue = input$eval,
      parameters = params
    ),
    
    database = as.list(registry_entry),
    
    summary = list(
      hits = n_hits,
      top_hit = top_hit,
      top_bitscore = top_bitscore,
      top_evalue = top_evalue
    )
  )
}
