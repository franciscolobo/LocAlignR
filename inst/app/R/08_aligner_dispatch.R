# inst/app/R/07_aligner_dispatch.R

aligner_program_choices <- function(aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")

  switch(
    aligner,
    "BLAST"   = c("blastp", "blastx", "blastn", "tblastn", "tblastx"),
    "DIAMOND" = c("blastp", "blastx"),
    stop("Unsupported aligner: ", aligner)
  )
}

run_aligner_as_xml <- function(
  aligner,
  program,
  query_fasta,
  db,
  evalue,
  remote = FALSE,
  params = list()
) {
#  cat("[debug] A. run_aligner_as_xml entered. aligner=", aligner, "\n")
  aligner <- toupper(aligner %||% "BLAST")
#  cat("[debug] B. aligner normalized=", aligner, "\n")

  if (identical(aligner, "DIAMOND")) {
#    cat("[debug] C. DIAMOND branch -- about to validate\n")

    shiny::validate(
      shiny::need(program %in% c("blastp", "blastx"), "DIAMOND supports only blastp and blastx."),
      shiny::need(!isTRUE(remote), "DIAMOND does not support remote databases."),
      shiny::need(grepl("\\.dmnd$", db, ignore.case = TRUE), "DIAMOND requires a .dmnd database.")
    )
#    cat("[debug] D. DIAMOND validate PASSED. program=", program, " remote=", remote, " db=", db, "\n")

    result <- run_diamond_as_xml(
      mode   = program,
      query  = query_fasta,
      db     = db,
      eval   = evalue,
      params = params
    )
#    cat("[debug] E. run_diamond_as_xml RETURNED\n")
    result
  } else {
    run_blast_as_xml(
      prog   = program,
      query  = query_fasta,
      db     = db,
      eval   = evalue,
      remote = remote,
      params = params
    )
  }
}

parse_aligner_xml_to_df <- function(xml_doc, aligner = "BLAST") {
  parse_alignment_xml_to_df(xml_doc = xml_doc, aligner = aligner)
}
