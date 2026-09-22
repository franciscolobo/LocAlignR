.make_blast_xml <- function(iterations_xml) {
  xml_text <- paste0(
    '<?xml version="1.0"?>',
    '<BlastOutput><BlastOutput_iterations>',
    iterations_xml,
    '</BlastOutput_iterations></BlastOutput>'
  )
  XML::xmlParse(xml_text, asText = TRUE, useInternalNodes = TRUE)
}

test_that("parse_blast_xml_to_df returns an empty frame with correct columns when there are no hits", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Query1</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)
  expect_equal(nrow(out), 0)
  expect_true(all(c("query_ID", "hit_ID", "bitscore", "eval") %in% names(out)))
})

test_that("parse_blast_xml_to_df parses a single hit correctly", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>MyQuery</Iteration_query-def>',
    '<Iteration_query-len>150</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>sp|P12345|TARGET</Hit_id>',
    '<Hit_hsps><Hsp>',
    '<Hsp_bit-score>200.5</Hsp_bit-score>',
    '<Hsp_evalue>1e-50</Hsp_evalue>',
    '<Hsp_query-from>10</Hsp_query-from>',
    '<Hsp_query-to>100</Hsp_query-to>',
    '</Hsp></Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  expect_equal(nrow(out), 1)
  expect_equal(out$query_ID[1], "MyQuery")
  expect_equal(out$hit_ID[1], "sp|P12345|TARGET")
  expect_equal(as.numeric(out$hit_length[1]), 91)
  expect_equal(round(as.numeric(out$query_fraction[1]), 2), 0.61)
  expect_equal(as.numeric(out$bitscore[1]), 200.5)
  expect_equal(as.numeric(out$eval[1]), 1e-50)
})

test_that("parse_blast_xml_to_df combines multiple iterations, skipping no-hit ones", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Q1</Iteration_query-def>',
    '<Iteration_query-len>50</Iteration_query-len>',
    '<Iteration_hits></Iteration_hits>',
    '</Iteration>',
    '<Iteration>',
    '<Iteration_query-def>Q2</Iteration_query-def>',
    '<Iteration_query-len>50</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>HitForQ2</Hit_id>',
    '<Hit_hsps><Hsp>',
    '<Hsp_bit-score>50</Hsp_bit-score>',
    '<Hsp_evalue>0.001</Hsp_evalue>',
    '<Hsp_query-from>1</Hsp_query-from>',
    '<Hsp_query-to>50</Hsp_query-to>',
    '</Hsp></Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)
  expect_equal(nrow(out), 1)
  expect_equal(out$query_ID[1], "Q2")
})
