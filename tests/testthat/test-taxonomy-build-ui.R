.source_app_file("14_taxonomy_build.R")

test_that("disabled taxonomy ignores stale controls", {
  expect_null(localignr_taxonomy_build_input(list()))
  expect_null(localignr_taxonomy_build_input(list(make_taxonomy = FALSE,
    make_taxonomy_method = "mapping", make_taxonomy_map = NULL)))
})

test_that("active taxonomy controls translate into backend configurations", {
  expect_identical(localignr_taxonomy_build_input(list(make_taxonomy = TRUE,
    make_taxonomy_method = "uniprot", make_taxonomy_taxid = "bad")), list(method = "uniprot"))
  expect_identical(localignr_taxonomy_build_input(list(make_taxonomy = TRUE,
    make_taxonomy_method = "single", make_taxonomy_taxid = " 9606 ")),
    list(method = "single", taxid = "9606"))
  path <- tempfile(fileext = ".tsv")
  on.exit(unlink(path), add = TRUE)
  writeLines(c("id\ttaxid", "seq1\t9606"), path)
  expect_identical(localignr_taxonomy_build_input(list(make_taxonomy = TRUE,
    make_taxonomy_method = "mapping", make_taxonomy_map = list(datapath = path))),
    list(method = "mapping", mapping_path = path))
})

test_that("invalid UI configurations fail before indexing", {
  expect_error(localignr_taxonomy_build_input(list(make_taxonomy = TRUE)), "assignment method")
  expect_error(localignr_taxonomy_build_input(list(make_taxonomy = TRUE,
    make_taxonomy_method = "single", make_taxonomy_taxid = "0")), "positive integer")
  expect_error(localignr_taxonomy_build_input(list(make_taxonomy = TRUE,
    make_taxonomy_method = "mapping")), "mapping TSV")
})
