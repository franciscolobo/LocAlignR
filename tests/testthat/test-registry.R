test_that("infer_type detects nucleotide vs protein from name/path", {
  expect_equal(infer_type("my_nt_db", "/x/y"), "nucl")
  expect_equal(infer_type("dna_seqs", "/x/y"), "nucl")
  expect_equal(infer_type("some_nucl_thing", "/x/y"), "nucl")
  expect_equal(infer_type("uniprot_sprot", "/x/y.faa"), "prot")
  expect_equal(infer_type("random_name", "/random/path"), "prot")
})

test_that("make_db_registry_name appends backend suffix, unless already present", {
  expect_equal(make_db_registry_name("myfish", "blast"), "myfish_blast")
  expect_equal(make_db_registry_name("myfish", "diamond"), "myfish_diamond")
  expect_equal(make_db_registry_name("myfish_blast", "diamond"), "myfish_blast")
  expect_equal(make_db_registry_name(" myfish ", "BLAST"), "myfish_blast")
})

test_that("normalize_registry_df returns a well-formed empty frame for NULL/empty input", {
  out <- normalize_registry_df(NULL)
  expect_equal(nrow(out), 0)
  expect_true(all(registry_schema_columns() %in% names(out)))

  out2 <- normalize_registry_df(data.frame())
  expect_equal(nrow(out2), 0)
})

test_that("normalize_registry_df fills defaults for missing optional columns", {
  df <- data.frame(name = "foo", path = "/tmp/foo", type = "prot", stringsAsFactors = FALSE)
  out <- normalize_registry_df(df)

  expect_equal(out$backend, "blast")     # default when blank
  expect_equal(out$source, "user")       # default when blank
  expect_equal(out$title, "foo")         # falls back to name when blank
  expect_false(out$has_metadata)         # NA -> FALSE
})

test_that("allowed_db_choices_for_program filters correctly per aligner/program", {
  reg <- normalize_registry_df(data.frame(
    name    = c("p_blast", "n_blast", "p_diamond"),
    path    = c("/a", "/b", "/c.dmnd"),
    type    = c("prot", "nucl", "prot"),
    backend = c("blast", "blast", "diamond"),
    stringsAsFactors = FALSE
  ))

  blastp_choices <- allowed_db_choices_for_program(reg, "blastp", "BLAST")
  expect_true("p_blast" %in% blastp_choices)
  expect_false("n_blast" %in% blastp_choices)
  expect_false("p_diamond" %in% blastp_choices)

  blastn_choices <- allowed_db_choices_for_program(reg, "blastn", "BLAST")
  expect_true("n_blast" %in% blastn_choices)
  expect_false("p_blast" %in% blastn_choices)

  diamond_choices <- allowed_db_choices_for_program(reg, "blastp", "DIAMOND")
  expect_equal(diamond_choices, "p_diamond")
})

test_that("resolve_db_selection resolves nr/nt shortcuts for BLAST without touching the registry", {
  reg <- normalize_registry_df(data.frame(
    name = "irrelevant", path = "/x", type = "prot", backend = "blast",
    stringsAsFactors = FALSE
  ))

  nr <- resolve_db_selection("nr", reg, program = "blastp", aligner = "BLAST")
  expect_equal(nr$db_path, "nr")
  expect_equal(nr$db_type, "prot")
  expect_true(nr$remote)

  nt <- resolve_db_selection("nt", reg, program = "blastn", aligner = "BLAST")
  expect_equal(nt$db_type, "nucl")
  expect_true(nt$remote)
})

test_that("resolve_db_selection resolves a normal registry entry", {
  reg <- normalize_registry_df(data.frame(
    name = "myprot_blast", path = "/data/myprot", type = "prot", backend = "blast",
    stringsAsFactors = FALSE
  ))

  res <- resolve_db_selection("myprot_blast", reg, program = "blastp", aligner = "BLAST")
  expect_equal(res$db_path, "/data/myprot")
  expect_equal(res$db_type, "prot")
  expect_false(res$remote)
  expect_equal(res$backend, "blast")
})

test_that("resolve_db_selection rejects an unknown database name", {
  reg <- normalize_registry_df(data.frame(
    name = "onlyone", path = "/x", type = "prot", backend = "blast",
    stringsAsFactors = FALSE
  ))

  expect_shiny_validation_error(
    resolve_db_selection("does_not_exist", reg, program = "blastp", aligner = "BLAST"),
    regexp = "Unknown DB"
  )
})

test_that("resolve_db_selection rejects aligner/backend mismatches", {
  reg <- normalize_registry_df(data.frame(
    name = "prot_diamond", path = "/x.dmnd", type = "prot", backend = "diamond",
    stringsAsFactors = FALSE
  ))

  expect_shiny_validation_error(
    resolve_db_selection("prot_diamond", reg, program = "blastp", aligner = "BLAST"),
    regexp = "not registered for BLAST"
  )
})

test_that("resolve_db_selection rejects program/type mismatches", {
  reg <- normalize_registry_df(data.frame(
    name = "nuclonly", path = "/x", type = "nucl", backend = "blast",
    stringsAsFactors = FALSE
  ))

  expect_shiny_validation_error(
    resolve_db_selection("nuclonly", reg, program = "blastp", aligner = "BLAST"),
    regexp = "protein DB"
  )
})
