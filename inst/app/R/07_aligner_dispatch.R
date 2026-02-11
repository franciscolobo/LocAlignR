# inst/app/R/03_aligner_dispatch.R

run_aligner_as_xml <- function(aligner, program, query_fasta, db, evalue, remote = FALSE) {
  aligner <- toupper(aligner %||% "BLAST")

  if (identical(aligner, "DIAMOND")) {
    shiny::validate(
      shiny::need(program %in% c("blastp", "blastx"), "DIAMOND supports only blastp and blastx."),
      shiny::need(!isTRUE(remote), "DIAMOND does not support remote databases."),
      shiny::need(grepl("\\.dmnd$", db, ignore.case = TRUE), "DIAMOND requires a .dmnd database.")
    )
    run_diamond_as_xml(mode = program, query = query_fasta, db = db, eval = evalue)
  } else {
    run_blast_as_xml(prog = program, query = query_fasta, db = db, eval = evalue, remote = remote)
  }
}
