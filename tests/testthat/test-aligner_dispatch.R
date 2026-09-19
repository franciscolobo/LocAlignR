test_that("aligner_program_choices returns the correct program sets", {
  expect_equal(
    aligner_program_choices("BLAST"),
    c("blastp", "blastx", "blastn", "tblastn", "tblastx")
  )
  expect_equal(aligner_program_choices("DIAMOND"), c("blastp", "blastx"))
  expect_equal(aligner_program_choices(), aligner_program_choices("BLAST"))  # default
})

test_that("aligner_program_choices rejects unsupported aligners", {
  expect_error(aligner_program_choices("FOOALIGN"), "Unsupported aligner")
})
