# inst/app/R/07_aligner_dispatch.R

aligner_program_choices <- function(aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")
  
  switch(
    aligner,
    "BLAST"   = c("blastp", "blastx", "blastn", "tblastn"),
    "DIAMOND" = c("blastp", "blastx"),
    stop("Unsupported aligner: ", aligner)
  )
}

run_aligner_as_xml <- function(aligner, program, query_fasta, db, evalue, remote = FALSE) {
  aligner <- toupper(aligner %||% "BLAST")
  
  if (identical(aligner, "DIAMOND")) {
    shiny::validate(
      shiny::need(program %in% c("blastp", "blastx"), "DIAMOND supports only blastp and blastx."),
      shiny::need(!isTRUE(remote), "DIAMOND does not support remote databases."),
      shiny::need(grepl("\\.dmnd$", db, ignore.case = TRUE), "DIAMOND requires a .dmnd database.")
    )
    
    run_diamond_as_xml(
      mode  = program,
      query = query_fasta,
      db    = db,
      eval  = evalue
    )
  } else {
    run_blast_as_xml(
      prog   = program,
      query  = query_fasta,
      db     = db,
      eval   = evalue,
      remote = remote
    )
  }
}

parse_aligner_xml_to_df <- function(xml_doc, aligner = "BLAST") {
  parse_alignment_xml_to_df(xml_doc = xml_doc, aligner = aligner)
}