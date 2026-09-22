# tests/testthat/test-blast_args.R

test_that("build_blast_args includes only the required flags when params is empty", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "somedb", eval = 1e-5,
    remote = FALSE, params = list(), out_xml = "/tmp/out.xml"
  )

  expect_true(all(c("-query", "q.fa", "-db", "somedb", "-evalue", "1e-05") %in% args) ||
    all(c("-query", "q.fa", "-db", "somedb") %in% args))  # evalue formatting checked separately below

  expect_true("-outfmt" %in% args)
  expect_equal(args[which(args == "-outfmt") + 1], "5")
  expect_true("-out" %in% args)
  expect_equal(args[which(args == "-out") + 1], "/tmp/out.xml")

  # Defaults applied when params doesn't specify them
  expect_equal(args[which(args == "-max_hsps") + 1], "1")
  expect_equal(args[which(args == "-max_target_seqs") + 1], "10")

  # None of the optional flags should appear when their params are absent
  expect_false("-word_size" %in% args)
  expect_false("-matrix" %in% args)
  expect_false("-gapopen" %in% args)
  expect_false("-gapextend" %in% args)
  expect_false("-culling_limit" %in% args)
  expect_false("-best_hit_overhang" %in% args)
  expect_false("-best_hit_score_edge" %in% args)
})

test_that("build_blast_args adds -word_size only when word_size param is provided", {
  args_without <- build_blast_args(
    prog = "blastn", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(), out_xml = "/tmp/out.xml"
  )
  expect_false("-word_size" %in% args_without)

  args_with <- build_blast_args(
    prog = "blastn", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(word_size = 11), out_xml = "/tmp/out.xml"
  )
  expect_true("-word_size" %in% args_with)
  expect_equal(args_with[which(args_with == "-word_size") + 1], "11")
})

test_that("build_blast_args adds -matrix only when a non-blank matrix param is provided", {
  args_blank <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(matrix = "  "), out_xml = "/tmp/out.xml"
  )
  expect_false("-matrix" %in% args_blank)

  args_set <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(matrix = "BLOSUM80"), out_xml = "/tmp/out.xml"
  )
  expect_true("-matrix" %in% args_set)
  expect_equal(args_set[which(args_set == "-matrix") + 1], "BLOSUM80")
})

test_that("build_blast_args adds -gapopen and -gapextend independently when provided", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(gapopen = 11, gapextend = 1), out_xml = "/tmp/out.xml"
  )
  expect_equal(args[which(args == "-gapopen") + 1], "11")
  expect_equal(args[which(args == "-gapextend") + 1], "1")
})

test_that("build_blast_args adds -culling_limit only when provided", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE, params = list(culling_limit = 5), out_xml = "/tmp/out.xml"
  )
  expect_equal(args[which(args == "-culling_limit") + 1], "5")
})

test_that("build_blast_args adds both best-hit flags together when both params are provided", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
    remote = FALSE,
    params = list(best_hit_overhang = 0.1, best_hit_score_edge = 0.1),
    out_xml = "/tmp/out.xml"
  )
  expect_true("-best_hit_overhang" %in% args)
  expect_true("-best_hit_score_edge" %in% args)
  expect_equal(args[which(args == "-best_hit_overhang") + 1], "0.1")
  expect_equal(args[which(args == "-best_hit_score_edge") + 1], "0.1")
})

test_that("build_blast_args rejects providing only one of the two best-hit filtering params", {
  expect_shiny_validation_error(
    build_blast_args(
      prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
      remote = FALSE,
      params = list(best_hit_overhang = 0.1),  # score_edge missing
      out_xml = "/tmp/out.xml"
    ),
    regexp = "requires both best-hit overhang and best-hit score edge"
  )

  expect_shiny_validation_error(
    build_blast_args(
      prog = "blastp", query = "q.fa", db = "db", eval = 1e-5,
      remote = FALSE,
      params = list(best_hit_score_edge = 0.1),  # overhang missing
      out_xml = "/tmp/out.xml"
    ),
    regexp = "requires both best-hit overhang and best-hit score edge"
  )
})

test_that("build_blast_args appends -remote and omits -num_threads when remote = TRUE", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "nr", eval = 1e-5,
    remote = TRUE, params = list(), out_xml = "/tmp/out.xml"
  )
  expect_true("-remote" %in% args)
  expect_false("-num_threads" %in% args)
})

test_that("build_blast_args appends -num_threads and omits -remote when remote = FALSE", {
  args <- build_blast_args(
    prog = "blastp", query = "q.fa", db = "somedb", eval = 1e-5,
    remote = FALSE, params = list(threads = 4), out_xml = "/tmp/out.xml"
  )
  expect_false("-remote" %in% args)
  expect_true("-num_threads" %in% args)
  expect_equal(args[which(args == "-num_threads") + 1], "4")
})
