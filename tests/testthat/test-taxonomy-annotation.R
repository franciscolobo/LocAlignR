test_that("lineage lookup resolves merged IDs and leaves unknown IDs unassigned", {
  dir <- tempfile(); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
  writeLines(c("1\t|\t1\t|\tno rank\t|\t", "40674\t|\t1\t|\tclass\t|\t",
               "9606\t|\t40674\t|\tspecies\t|\t"), file.path(dir, "nodes.dmp"))
  writeLines(c("1\t|\troot\t|\t\t|\tscientific name\t|",
               "40674\t|\tMammalia\t|\t\t|\tscientific name\t|",
               "9606\t|\tHomo sapiens\t|\t\t|\tscientific name\t|",
               "9606\t|\thuman\t|\t\t|\tcommon name\t|"), file.path(dir, "names.dmp"))
  writeLines("999\t|\t9606\t|", file.path(dir, "merged.dmp"))
  idx <- localignr_taxonomy_index(dir)
  out <- localignr_taxonomy_lineages(c("9606", "999", "42", NA, "9606"), idx)
  expect_equal(out$taxon_id, c("9606", "9606", NA, NA, "9606"))
  expect_equal(out$taxon_class[1], "Mammalia")
  expect_equal(out$taxon_species[1], "Homo sapiens")
  expect_equal(out$taxon_lineage[1], "root; Mammalia; Homo sapiens")
  expect_equal(localignr_taxonomy_find("homo", idx)$id, "9606")
  expect_equal(localignr_taxonomy_find("999", idx)$id, "9606")
  mapping <- data.frame(id = "sp|P12345|TEST_HUMAN", taxid = "9606")
  ann <- localignr_taxonomy_annotate(c("P12345", "unmapped", "P12345"), empty_subject_meta(), mapping, idx)
  expect_equal(ann$id, c("P12345", "unmapped"))
  expect_equal(ann$taxon_id, c("9606", NA))
})

test_that("subject metadata joins preserve row count, order and exact identifiers", {
  meta <- data.frame(id = c("a|shared", "b|shared", "sp|P12345|TEST_HUMAN"), taxid = c("1", "2", "9606"))
  hits <- data.frame(hit_ID = c("b|shared", "shared", "P12345", "b|shared"))
  out <- localignr_join_subject_meta(hits, meta)
  expect_equal(out$hit_ID, hits$hit_ID)
  expect_equal(out$taxid, c("2", NA, "9606", "2"))
  expect_equal(localignr_join_subject_meta(hits, empty_subject_meta()), hits)
})
