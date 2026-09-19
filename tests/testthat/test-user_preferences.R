test_that("build_current_preferences captures fields with correct defaults", {
  mock_input <- list(aligner = "BLAST", program = "blastp", db = "nr")

  prefs <- build_current_preferences(mock_input, params = list(threads = 2L))

  expect_equal(prefs$aligner, "BLAST")
  expect_equal(prefs$evalue, "1e-5")   # default when input$eval is absent
  expect_false(prefs$show_advanced_params)
  expect_equal(prefs$parameters$threads, 2L)
})
