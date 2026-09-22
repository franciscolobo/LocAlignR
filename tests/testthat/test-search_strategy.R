test_that("build_search_strategy captures the expected fields from a mock input list", {
  mock_input <- list(
    aligner = "DIAMOND",
    program = "blastx",
    db = "mydb_diamond",
    eval = "1e-10",
    aligner_preset = "Sensitive",
    show_advanced_params = TRUE
  )

  strat <- build_search_strategy(mock_input, params = list(max_target_seqs = 20L))

  expect_equal(strat$schema, "localignr_search_strategy_v1")
  expect_equal(strat$aligner, "DIAMOND")
  expect_equal(strat$database, "mydb_diamond")
  expect_equal(strat$parameters$max_target_seqs, 20L)
})

test_that("write_search_strategy / read_search_strategy round-trip correctly", {
  mock_input <- list(
    aligner = "BLAST", program = "blastp", db = "nr",
    eval = "1e-5", aligner_preset = "Default", show_advanced_params = FALSE
  )
  strat <- build_search_strategy(mock_input, params = list(max_hsps = 1L))

  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))

  write_search_strategy(strat, tmp)
  strat_back <- read_search_strategy(tmp)

  expect_equal(strat_back$aligner, "BLAST")
  expect_equal(strat_back$database, "nr")
  expect_equal(strat_back$parameters$max_hsps, 1L)
})

test_that("read_search_strategy rejects files with an unrecognized schema tag", {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp))
  jsonlite::write_json(list(schema = "some_other_schema"), tmp, auto_unbox = TRUE)

  expect_error(read_search_strategy(tmp), "Unsupported search strategy format")
})
