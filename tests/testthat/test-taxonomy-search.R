test_that("taxonomy filters are parsed and validated", {
  expect_null(localignr_taxonomy_filter("none", "invalid"))
  expect_identical(localignr_taxonomy_filter("include", "9606, 10090 9606"),
                   list(mode = "include", ids = c("9606", "10090")))
  for (bad in c("", "0", "-1", "9606;10090", "9606.5", "NA", "9606,"))
    expect_error(localignr_taxonomy_filter("include", bad))
  expect_error(localignr_taxonomy_filter("bad", "9606"))
})

test_that("native arguments match each engine", {
  for (mode in c("include", "exclude")) {
    filter <- localignr_taxonomy_filter(mode, "9606,10090")
    b <- if (mode == "include") "-taxids" else "-negative_taxids"
    d <- if (mode == "include") "--taxonlist" else "--taxon-exclude"
    expect_identical(localignr_taxonomy_search_args(filter, "blast"), c(b, "9606,10090"))
    expect_identical(localignr_taxonomy_search_args(filter, "diamond"), c(d, "9606,10090"))
    args <- build_blast_args("blastp", "q.faa", "db", 1e-5, FALSE,
                             list(taxonomy_filter = filter, threads = 1), "out.xml")
    expect_identical(tail(args, 2), c(b, "9606,10090"))
    expect_error(localignr_taxonomy_search_args(filter, "blast", remote = TRUE))
  }
  expect_identical(localignr_taxonomy_search_args(NULL, "blast"), character())
})

test_that("incompatible databases and missing resources fail closed", {
  filter <- localignr_taxonomy_filter("include", "9606")
  expect_null(localignr_taxonomy_search_config(NULL, list(remote = TRUE)))
  expect_error(localignr_taxonomy_search_config(filter, list(remote = TRUE, has_taxonomy = TRUE)), "local database")
  expect_error(localignr_taxonomy_search_config(filter, list(has_taxonomy = FALSE)), "local database")
  expect_error(localignr_taxonomy_search_config(filter, list(has_taxonomy = TRUE, taxonomy_dir = tempfile())), "snapshot")
})


test_that("search strategies retain taxonomy filters", {
  f <- list(mode = "exclude", ids = c("9606", "10090"), snapshot = "test-snapshot")
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  write_search_strategy(build_search_strategy(list(), list(taxonomy_filter = f)), path)
  expect_equal(read_search_strategy(path)$parameters$taxonomy_filter, f)
})
