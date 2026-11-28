# Pure logic and registry regression tests. No network, no real user data.
.source_app_file("13_taxonomy.R")
.source_app_file("14_taxonomy_build.R")

# Synthetic, checksummed snapshot exercises the same path as a real snapshot.
make_taxonomy_fixture <- function(root) {
  dir.create(root, recursive = TRUE)
  files <- unlist(lapply(localignr_taxonomy_specs(), `[[`, "files"), use.names = FALSE)
  for (f in files) writeLines("fixture", file.path(root, f))
  writeLines(c("1\t|\t1\t|\tno rank\t|", "9606\t|\t1\t|\tspecies\t|",
               "10090\t|\t1\t|\tspecies\t|"), file.path(root, "nodes.dmp"))
  writeLines("99999\t|\t9606\t|", file.path(root, "merged.dmp"))
  hashes <- setNames(vapply(file.path(root, files), localignr_taxonomy_sha256, "", USE.NAMES = FALSE), files)
  jsonlite::write_json(list(files = as.list(hashes)), file.path(root, "manifest.json"), auto_unbox = TRUE)
  root
}

test_that("registry keeps taxonomy independent of metadata and round-trips old/new entries", {
  root <- tempfile("registry-taxonomy-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "user_dbs.yml")
  yaml::write_yaml(list(old_blast = list(path = "/fake/old", type = "prot")), path)
  old <- load_user_dbs(path)
  expect_false(old$has_taxonomy)
  expect_identical(old$taxonomy_dir, "")
  newer <- normalize_registry_df(data.frame(name = "new_diamond", path = "/fake/new.dmnd",
    type = "prot", backend = "diamond", has_taxonomy = TRUE, taxonomy_source = "NCBI",
    taxonomy_dir = "/fake/taxonomy", taxonomy_snapshot = "snapshot1", taxonomy_map_path = "/fake/map.tsv"))
  all <- rbind(old, newer)
  save_user_dbs(all, path)
  expect_identical(load_user_dbs(path), all)
  resolved <- resolve_db_selection("new_diamond", all, "blastp", "DIAMOND")
  expect_true(resolved$has_taxonomy)
  expect_identical(resolved$taxonomy_map_path, "/fake/map.tsv")
  expect_false(resolve_db_selection("nr", all, "blastp")$has_taxonomy)
})

test_that("taxonomy builder generates exact engine-specific mappings and resolves merged IDs", {
  root <- tempfile("taxonomy-build-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  snap <- make_taxonomy_fixture(file.path(root, "snapshot"))
  fasta <- file.path(root, "seqs.faa")
  writeLines(c(">sp|P00001|TEST_HUMAN protein OS=Human OX=99999 GN=A", "MKTLLVAA",
               ">sp|P00002|TEST_MOUSE protein OS=Mouse OX=10090", "MWTLLVAA"), fasta)
  b <- localignr_taxonomy_prepare_build(fasta, "blast", file.path(root, "blast"), taxonomy_dir = snap)
  d <- localignr_taxonomy_prepare_build(fasta, "diamond", file.path(root, "diamond"), taxonomy_dir = snap)
  expect_identical(b$mapping, d$mapping)
  expect_identical(b$mapping$taxid, c("9606", "10090"))
  expect_true(all(c("-parse_seqids", "-blastdb_version", "-taxid_map") %in% b$args))
  expect_true(all(c("--no-parse-seqids", "--taxonmap", "--taxonnodes", "--taxonnames") %in% d$args))
  expect_identical(readLines(b$native_map_path), c("sp|P00001|TEST_HUMAN\t9606", "sp|P00002|TEST_MOUSE\t10090"))
  expect_identical(readLines(d$native_map_path)[1L], "accession\taccession.version\ttaxid\tgi")
  expect_identical(readLines(d$native_map_path)[2L], "sp|P00001|TEST_HUMAN\tsp|P00001|TEST_HUMAN\t9606\t0")
  expect_identical(localignr_taxonomy_read_map(b$map_path), b$mapping)
})

test_that("custom taxonomy assignments reject incomplete, duplicate and invalid IDs", {
  root <- tempfile("taxonomy-custom-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  snap <- make_taxonomy_fixture(file.path(root, "snapshot"))
  fasta <- file.path(root, "seqs.faa")
  writeLines(c(">seq1.1", "MKTLLVAA", ">seq1.2", "MWTLLVAA"), fasta)
  args <- list(fasta = fasta, backend = "diamond", directory = file.path(root, "output"), taxonomy_dir = snap)
  single <- do.call(localignr_taxonomy_prepare_build, c(args, list(method = "single", taxid = "9606")))
  expect_identical(single$mapping$taxid, rep("9606", 2L))
  expect_error(do.call(localignr_taxonomy_prepare_build, c(args, list(method = "single", taxid = "0"))), "positive integer")
  expect_error(do.call(localignr_taxonomy_prepare_build, c(args, list(method = "single", taxid = "123456"))), "Unknown or deleted")
  m <- file.path(root, "map.tsv")
  writeLines(c("id\ttaxid", "seq1.2\t10090", "seq1.1\t9606"), m)
  custom <- do.call(localignr_taxonomy_prepare_build, c(args, list(method = "mapping", mapping_path = m)))
  expect_identical(custom$mapping$taxid, c("9606", "10090"))
  writeLines(c("id\ttaxid", "seq1.1\t9606"), m)
  expect_error(do.call(localignr_taxonomy_prepare_build, c(args, list(method = "mapping", mapping_path = m))), "match all FASTA")
  writeLines(c("id\ttaxid", "seq1.1\t9606", "seq1.1\t10090"), m)
  expect_error(localignr_taxonomy_read_map(m), "unique")
  writeLines(c(">seq1", "MKTLLVAA", ">seq1", "MWTLLVAA"), fasta)
  expect_error(localignr_taxonomy_fasta_headers(fasta), "unique")
})

test_that("DIAMOND mapping count must be present and complete", {
  expect_true(localignr_taxonomy_validate_diamond_log("", "  Database sequences mapped to taxid  2\n", 2L))
  expect_error(localignr_taxonomy_validate_diamond_log("", "Database sequences mapped to taxid  1", 2L), "complete taxonomy")
  expect_error(localignr_taxonomy_validate_diamond_log("", "Other output", 2L), "complete taxonomy")
})
