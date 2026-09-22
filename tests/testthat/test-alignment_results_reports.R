test_that("render_clicked_summary_table labels query and hit coordinates distinctly", {
  row <- data.frame(
    query_ID       = "Q1",
    hit_ID         = "H1",
    hsp_q_begin    = "1",
    hsp_q_end      = "50",
    hsp_h_begin    = "500",
    hsp_h_end      = "549",
    hit_length     = "50",
    query_fraction = "0.5",
    bitscore       = "77",
    eval           = "1e-15",
    stringsAsFactors = FALSE
  )

  subject_meta <- empty_subject_meta()

  out <- render_clicked_summary_table(row, subject_meta)

  qb <- out$Value[out$Field == "Query begin"]
  qe <- out$Value[out$Field == "Query end"]
  hb <- out$Value[out$Field == "Hit begin"]
  he <- out$Value[out$Field == "Hit end"]

  expect_equal(qb, "1")
  expect_equal(qe, "50")
  expect_equal(hb, "500")
  expect_equal(he, "549")

  # Guards against the historical bug where "Hit begin"/"Hit end" were
  # actually populated from query coordinates.
  expect_false(identical(hb, qb))
  expect_false(identical(he, qe))
})

test_that("build_and_save_alignment_xlsx_report writes distinct, correctly-labeled query and hit coordinate columns", {
  skip_if_not_installed("openxlsx")

  xml_text <- paste0(
    '<?xml version="1.0"?>',
    '<BlastOutput><BlastOutput_iterations>',
    '<Iteration>',
    '<Iteration_query-def>Q1</Iteration_query-def>',
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
    '</Iteration>',
    '</BlastOutput_iterations></BlastOutput>'
  )
  doc <- XML::xmlParse(xml_text, asText = TRUE, useInternalNodes = TRUE)
  df  <- parse_blast_xml_to_df(doc)

  tmp <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp))

  build_and_save_alignment_xlsx_report(
    tmp, xml_doc = doc, df = df, subject_meta = empty_subject_meta()
  )

  # read.xlsx()'s header sanitization (spaces -> dots) isn't reliably
  # suppressed by check.names in all openxlsx versions, so read the header
  # row and body raw (colNames = FALSE) and match positionally instead of
  # trusting read.xlsx()'s auto-generated data.frame names.
  header <- as.character(openxlsx::read.xlsx(tmp, sheet = 1, colNames = FALSE, rows = 1)[1, ])
  body   <- openxlsx::read.xlsx(tmp, sheet = 1, colNames = FALSE, startRow = 2)

  expect_true(all(c("Query begin", "Query end", "Hit begin", "Hit end") %in% header))

  qb_col <- which(header == "Query begin")
  hb_col <- which(header == "Hit begin")

  expect_equal(as.character(body[1, qb_col]), "1")
  expect_equal(as.character(body[1, hb_col]), "500")
})

test_that(".render_blast_results_dt_impl renders e-value in 2-decimal scientific notation via a JS column renderer", {
  skip_if_not_installed("DT")

  df <- data.frame(
    query_ID       = "Q1",
    hit_ID         = "H1",
    hsp_q_begin    = "1",
    hsp_q_end      = "50",
    hsp_h_begin    = "500",
    hsp_h_end      = "549",
    hit_length     = "50",
    query_fraction = "0.5",
    bitscore       = "77",
    eval           = "3.7e-158",
    stringsAsFactors = FALSE
  )

  widget <- render_alignment_results_dt(df = df, subject_meta = empty_subject_meta())

  # attr(widget$x, "colnames") includes a leading " " entry for the
  # rownames column, so which(...) returns a 1-based *position* in that
  # vector -- one more than DT's own 0-based JS `targets` index (rownames
  # sit at JS index 0, so "eval" being the Nth element of colnames means
  # its JS target is N - 1).
  eval_col_position <- which(attr(widget$x, "colnames") == "eval")
  eval_target <- eval_col_position - 1

  col_defs <- widget$x$options$columnDefs

  # Use == rather than identical(): DT stores `targets` inconsistently as
  # integer in some columnDefs and double in others, so identical() can
  # spuriously fail on a type mismatch even when the values match.
  matching <- Filter(function(cd) !is.null(cd$targets) && isTRUE(cd$targets == eval_target), col_defs)

  expect_true(length(matching) >= 1)

  render_texts <- vapply(matching, function(cd) paste(cd$render, collapse = "\n"), character(1))
  expect_true(any(grepl("toExponential(2)", render_texts, fixed = TRUE)))
})

test_that("build_and_save_alignment_html_report renders e-value in 2-decimal scientific notation via a JS column renderer", {
  skip_if_not_installed("DT")

  xml_text <- paste0(
    '<?xml version="1.0"?>',
    '<BlastOutput><BlastOutput_iterations>',
    '<Iteration>',
    '<Iteration_query-def>Q1</Iteration_query-def>',
    '<Iteration_query-len>100</Iteration_query-len>',
    '<Iteration_hits><Hit>',
    '<Hit_id>H1</Hit_id>',
    '<Hit_hsps><Hsp>',
    '<Hsp_bit-score>77</Hsp_bit-score>',
    '<Hsp_evalue>3.7e-158</Hsp_evalue>',
    '<Hsp_query-from>1</Hsp_query-from>',
    '<Hsp_query-to>50</Hsp_query-to>',
    '<Hsp_hit-from>500</Hsp_hit-from>',
    '<Hsp_hit-to>549</Hsp_hit-to>',
    '</Hsp></Hit_hsps>',
    '</Hit></Iteration_hits>',
    '</Iteration>',
    '</BlastOutput_iterations></BlastOutput>'
  )
  doc <- XML::xmlParse(xml_text, asText = TRUE, useInternalNodes = TRUE)
  df  <- parse_blast_xml_to_df(doc)

  tmp <- tempfile(fileext = ".html")
  on.exit(unlink(tmp))

  build_and_save_alignment_html_report(
    tmp, xml_doc = doc, df = df, subject_meta = empty_subject_meta()
  )

  html_lines <- readLines(tmp, warn = FALSE)
  html_text <- paste(html_lines, collapse = "\n")

  # The saved widget's JS payload should contain the renderer, confirming
  # it was embedded into the self-contained HTML file rather than only
  # existing transiently in the R session.
  expect_true(grepl("toExponential(2)", html_text, fixed = TRUE))
})
