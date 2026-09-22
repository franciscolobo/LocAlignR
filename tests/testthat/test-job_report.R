test_that("build_job_report picks the correct top hit by bitscore, not by row order", {
  results_df <- data.frame(
    hit_ID   = c("LowScoreHit", "TopScoreHit", "MidScoreHit"),
    bitscore = c("10", "500", "200"),
    eval     = c("0.01", "1e-100", "1e-50"),
    stringsAsFactors = FALSE
  )

  report <- build_job_report(
    input = list(aligner = "BLAST", program = "blastp", db = "nr", eval = "1e-5"),
    registry_entry = list(),
    results_df = results_df,
    params = list()
  )

  expect_equal(report$summary$hits, 3)
  expect_equal(report$summary$top_hit, "TopScoreHit")
  expect_equal(report$summary$top_bitscore, 500)
  expect_equal(report$summary$top_evalue, 1e-100)
})

test_that("build_job_report reports NA summary fields, not empty/zero-length values, when there are no hits", {
  results_df <- data.frame(
    hit_ID   = character(),
    bitscore = character(),
    eval     = character(),
    stringsAsFactors = FALSE
  )

  report <- build_job_report(
    input = list(aligner = "BLAST", program = "blastp", db = "nr", eval = "1e-5"),
    registry_entry = list(),
    results_df = results_df,
    params = list()
  )

  expect_equal(report$summary$hits, 0)
  expect_true(is.na(report$summary$top_hit))
  expect_equal(length(report$summary$top_hit), 1)  # guards against the historical character(0) bug
  expect_true(is.na(report$summary$top_bitscore))
  expect_true(is.na(report$summary$top_evalue))
})

test_that("build_job_report round-trips cleanly through yaml::write_yaml/read_yaml", {
  skip_if_not_installed("yaml")

  results_df <- data.frame(
    hit_ID   = "OnlyHit",
    bitscore = "42.5",
    eval     = "0.0003",
    stringsAsFactors = FALSE
  )

  report <- build_job_report(
    input = list(aligner = "DIAMOND", program = "blastx", db = "mydb_diamond", eval = "1e-5"),
    registry_entry = list(name = "mydb_diamond", path = "/x.dmnd"),
    results_df = results_df,
    params = list(sensitivity = "sensitive")
  )

  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp))

  yaml::write_yaml(report, tmp)
  back <- yaml::read_yaml(tmp)

  expect_equal(back$summary$top_hit, "OnlyHit")
  expect_equal(back$summary$top_bitscore, 42.5)
})
