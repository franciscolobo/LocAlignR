test_that("wrap_alignment returns a single empty string for an empty query", {
  expect_equal(wrap_alignment("", "", ""), "")
})

test_that("wrap_alignment produces a single Query/Midline/Hit block for short input", {
  out <- wrap_alignment("ACGT", "||||", "ACGT", width = 40)
  expect_match(out, "Query:.*ACGT")
  expect_match(out, "Midline:.*\\|\\|\\|\\|")
  expect_match(out, "Hit:.*ACGT")
  expect_false(grepl("\\n\\n", out))  # single chunk, no blank-line separator
})

test_that("wrap_alignment_with_coords computes forward-strand coordinates without gaps", {
  out <- wrap_alignment_with_coords(
    qseq = "ACGT", mid = "||||", hseq = "ACGT",
    q_from = 1, q_to = 4, h_from = 1, h_to = 4, width = 40
  )
  expect_match(out, "Query\\s+1\\s+ACGT\\s+4")
  expect_match(out, "Sbjct\\s+1\\s+ACGT\\s+4")
})

test_that("wrap_alignment_with_coords excludes gap characters from position counts", {
  out <- wrap_alignment_with_coords(
    qseq = "AC-GT", mid = "|| ||", hseq = "ACTGT",
    q_from = 1, q_to = 4, h_from = 1, h_to = 5, width = 40
  )
  expect_match(out, "Query\\s+1\\s+AC-GT\\s+4")
  expect_match(out, "Sbjct\\s+1\\s+ACTGT\\s+5")
})

test_that("wrap_alignment_with_coords handles reverse-strand hit coordinates", {
  out <- wrap_alignment_with_coords(
    qseq = "ACGT", mid = "||||", hseq = "ACGT",
    q_from = 1, q_to = 4, h_from = 10, h_to = 7, width = 40
  )
  expect_match(out, "Sbjct\\s+10\\s+ACGT\\s+7")
})

test_that("wrap_alignment_with_coords chunks across multiple lines and advances positions", {
  out <- wrap_alignment_with_coords(
    qseq = "ACGTA", mid = "|||||", hseq = "ACGTA",
    q_from = 1, q_to = 5, h_from = 1, h_to = 5, width = 2
  )
  chunks <- strsplit(out, "\n\n")[[1]]
  expect_equal(length(chunks), 3)
  expect_match(chunks[1], "Query\\s+1\\s+AC\\s+2")
  expect_match(chunks[2], "Query\\s+3\\s+GT\\s+4")
  expect_match(chunks[3], "Query\\s+5\\s+A\\s+5")
})

test_that("wrap_alignment_with_coords reports missing sequence/coordinates gracefully", {
  expect_equal(
    wrap_alignment_with_coords("", "", "", 1, 1, 1, 1),
    "Alignment sequence is missing."
  )
  expect_equal(
    wrap_alignment_with_coords("ACGT", "||||", "ACGT", NA, 1, 1, 1),
    "Alignment coordinates are missing."
  )
})
