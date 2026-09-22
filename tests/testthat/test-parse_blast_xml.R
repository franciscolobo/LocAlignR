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

test_that("parse_blast_xml_to_df keeps each HSP's fields paired with its own hit when a hit has multiple HSPs", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>MultiHspQuery</Iteration_query-def>',
    '<Iteration_query-len>200</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>OnlyHit</Hit_id>',
    '<Hit_hsps>',
      '<Hsp>',
        '<Hsp_bit-score>300</Hsp_bit-score>',
        '<Hsp_evalue>1e-80</Hsp_evalue>',
        '<Hsp_query-from>1</Hsp_query-from>',
        '<Hsp_query-to>100</Hsp_query-to>',
      '</Hsp>',
      '<Hsp>',
        '<Hsp_bit-score>50</Hsp_bit-score>',
        '<Hsp_evalue>1e-05</Hsp_evalue>',
        '<Hsp_query-from>120</Hsp_query-from>',
        '<Hsp_query-to>150</Hsp_query-to>',
      '</Hsp>',
    '</Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  # Before the fix, cbind() recycling a length-1 hit_ID vector against a
  # length-2 HSP vector would still silently produce 2 rows here (recycled
  # hit_ID happens to be identical in this single-hit case) -- the real
  # danger only shows up with 2+ hits, covered in the next test. This test
  # pins down that both HSPs for one hit are preserved with their own,
  # non-cross-contaminated scores/e-values/coordinates.
  expect_equal(nrow(out), 2)
  expect_true(all(out$hit_ID == "OnlyHit"))

  expect_equal(as.numeric(out$bitscore), c(300, 50))
  expect_equal(as.numeric(out$eval), c(1e-80, 1e-05))
  expect_equal(as.numeric(out$hsp_q_begin), c(1, 120))
  expect_equal(as.numeric(out$hsp_q_end), c(100, 150))
  expect_equal(as.numeric(out$hit_length), c(100, 31))
})

test_that("parse_blast_xml_to_df does not cross-pair fields when multiple hits have differing HSP counts", {
  # This is the scenario that actually broke under the old flat-vector
  # cbind() approach: Hit A contributes 1 Hsp, Hit B contributes 2 Hsps.
  # hit_ID had length 2 (one per Hit), but bitscore/eval/coords had length 3
  # (one per Hsp) -- cbind() recycled hit_ID, misaligning every field for
  # Hit B's second HSP (and beyond, in larger real-world cases).
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Q</Iteration_query-def>',
    '<Iteration_query-len>500</Iteration_query-len>',
    '<Iteration_hits>',
      '<Hit>',
        '<Hit_id>HitA</Hit_id>',
        '<Hit_hsps><Hsp>',
          '<Hsp_bit-score>400</Hsp_bit-score>',
          '<Hsp_evalue>1e-100</Hsp_evalue>',
          '<Hsp_query-from>1</Hsp_query-from>',
          '<Hsp_query-to>200</Hsp_query-to>',
        '</Hsp></Hit_hsps>',
      '</Hit>',
      '<Hit>',
        '<Hit_id>HitB</Hit_id>',
        '<Hit_hsps>',
          '<Hsp>',
            '<Hsp_bit-score>90</Hsp_bit-score>',
            '<Hsp_evalue>1e-20</Hsp_evalue>',
            '<Hsp_query-from>210</Hsp_query-from>',
            '<Hsp_query-to>260</Hsp_query-to>',
          '</Hsp>',
          '<Hsp>',
            '<Hsp_bit-score>60</Hsp_bit-score>',
            '<Hsp_evalue>1e-10</Hsp_evalue>',
            '<Hsp_query-from>270</Hsp_query-from>',
            '<Hsp_query-to>300</Hsp_query-to>',
          '</Hsp>',
        '</Hit_hsps>',
      '</Hit>',
    '</Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  expect_equal(nrow(out), 3)
  expect_equal(out$hit_ID, c("HitA", "HitB", "HitB"))
  expect_equal(as.numeric(out$bitscore), c(400, 90, 60))
  expect_equal(as.numeric(out$eval), c(1e-100, 1e-20, 1e-10))
  expect_equal(as.numeric(out$hsp_q_begin), c(1, 210, 270))
  expect_equal(as.numeric(out$hsp_q_end), c(200, 260, 300))
})

test_that("parse_blast_xml_to_df skips a hit that has a Hit_id but no Hsp children, without misaligning subsequent hits", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Q</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits>',
      '<Hit>',
        '<Hit_id>Empty</Hit_id>',
        '<Hit_hsps></Hit_hsps>',
      '</Hit>',
      '<Hit>',
        '<Hit_id>Real</Hit_id>',
        '<Hit_hsps><Hsp>',
          '<Hsp_bit-score>10</Hsp_bit-score>',
          '<Hsp_evalue>0.01</Hsp_evalue>',
          '<Hsp_query-from>1</Hsp_query-from>',
          '<Hsp_query-to>50</Hsp_query-to>',
        '</Hsp></Hit_hsps>',
      '</Hit>',
    '</Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  expect_equal(nrow(out), 1)
  expect_equal(out$hit_ID[1], "Real")
})

test_that("parse_blast_xml_to_df extracts subject-side (hit) coordinates separately from query coordinates", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Q</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>H1</Hit_id>',
    '<Hit_hsps><Hsp>',
    '<Hsp_bit-score>77</Hsp_bit-score>',
    '<Hsp_evalue>1e-15</Hsp_evalue>',
    '<Hsp_query-from>1</Hsp_query-from>',
    '<Hsp_query-to>50</Hsp_query-to>',
    '<Hsp_hit-from>500</Hsp_hit-from>',
    '<Hsp_hit-to>549</Hsp_hit-to>',
    '</Hsp></Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  expect_equal(nrow(out), 1)
  expect_equal(as.numeric(out$hsp_q_begin), 1)
  expect_equal(as.numeric(out$hsp_q_end), 50)
  expect_equal(as.numeric(out$hsp_h_begin), 500)
  expect_equal(as.numeric(out$hsp_h_end), 549)
})

test_that("parse_blast_xml_to_df preserves reverse-strand hit coordinates (hit-from > hit-to) without reordering", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Q</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>H1</Hit_id>',
    '<Hit_hsps><Hsp>',
    '<Hsp_bit-score>77</Hsp_bit-score>',
    '<Hsp_evalue>1e-15</Hsp_evalue>',
    '<Hsp_query-from>1</Hsp_query-from>',
    '<Hsp_query-to>50</Hsp_query-to>',
    '<Hsp_hit-from>900</Hsp_hit-from>',
    '<Hsp_hit-to>851</Hsp_hit-to>',
    '</Hsp></Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)

  expect_equal(as.numeric(out$hsp_h_begin), 900)
  expect_equal(as.numeric(out$hsp_h_end), 851)
})

test_that("parse_blast_xml_to_df returns an empty frame that includes the hit-coordinate columns", {
  doc <- .make_blast_xml(paste0(
    '<Iteration>',
    '<Iteration_query-def>Query1</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits></Iteration_hits>',
    '</Iteration>'
  ))

  out <- parse_blast_xml_to_df(doc)
  expect_equal(nrow(out), 0)
  expect_true(all(c("hsp_h_begin", "hsp_h_end") %in% names(out)))
})
