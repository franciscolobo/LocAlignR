build_job_report <- function(
    input,
    registry_entry,
    results_df,
    params
) {
  
  n_hits <- nrow(results_df)
  
  top_hit <- if (n_hits > 0) {
    as.character(results_df$subject_id[1])
  } else {
    NA_character_
  }
  
  top_bitscore <- if (n_hits > 0) {
    results_df$bit_score[1]
  } else {
    NA
  }
  
  top_evalue <- if (n_hits > 0) {
    results_df$evalue[1]
  } else {
    NA
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