test_that("preset_choices and get_preset_values are consistent for both aligners", {
  expect_true("Default" %in% preset_choices("BLAST"))
  expect_true("Ultra-sensitive" %in% preset_choices("DIAMOND"))

  vals <- get_preset_values("DIAMOND", "Ultra-sensitive")
  expect_equal(vals$sensitivity, "ultra-sensitive")
  expect_equal(vals$max_target_seqs, 100L)
})

test_that("get_aligner_parameter_defs excludes program-restricted params when program is NULL", {
  defs_no_program <- get_aligner_parameter_defs("BLAST", program = NULL)
  expect_false("matrix" %in% names(defs_no_program))     # restricted to blastp/blastx/tblastn
  expect_true("max_target_seqs" %in% names(defs_no_program))  # unrestricted

  defs_blastp <- get_aligner_parameter_defs("BLAST", program = "blastp")
  expect_true("matrix" %in% names(defs_blastp))
  expect_false("word_size" %in% names(defs_blastp))       # restricted to blastn/tblastx
})

test_that("coerce_aligner_param_value handles numeric, optional, decimal, and select types", {
  numeric_def  <- list(input = "numeric", default = 10L)
  optional_def <- list(input = "numeric_optional", default = NULL)
  decimal_def  <- list(input = "numeric_decimal", default = NULL)
  select_def   <- list(input = "select", default = "default", choices = c("a", "b"))

  expect_equal(coerce_aligner_param_value("25", numeric_def), 25L)
  expect_equal(coerce_aligner_param_value(NA, numeric_def), 10L)  # falls back to default

  expect_null(coerce_aligner_param_value("", optional_def))
  expect_equal(coerce_aligner_param_value("7", optional_def), 7L)

  expect_equal(coerce_aligner_param_value("1.5", decimal_def), 1.5)
  expect_null(coerce_aligner_param_value("", decimal_def))

  expect_equal(coerce_aligner_param_value("", select_def), "default")  # blank -> default
  expect_equal(coerce_aligner_param_value("b", select_def), "b")
})

test_that("collect_aligner_params reads and coerces values from a mock input list", {
  mock_input <- list()
  mock_input[[aligner_param_input_id("max_target_seqs")]] <- "25"
  mock_input[[aligner_param_input_id("matrix")]] <- "BLOSUM80"
  mock_input[[aligner_param_input_id("threads")]] <- "4"
  mock_input[[aligner_param_input_id("max_hsps")]] <- "1"

  params <- collect_aligner_params(mock_input, aligner = "BLAST", program = "blastp")

  expect_equal(params$max_target_seqs, 25L)
  expect_equal(params$matrix, "BLOSUM80")
  expect_equal(params$threads, 4L)
})
