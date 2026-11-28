#!/usr/bin/env Rscript
# Run from the repository root in the existing localignr environment.
# Only writes to an isolated temporary registry and output directory.
main <- function() {
  root <- tempfile("localignr-taxonomy-smoke-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  env <- new.env(parent = globalenv())
  for (f in c("00_utils.R", "02_user_db_registry.R", "13_taxonomy.R",
              "14_taxonomy_build.R", "07_makeseqdb.R")) {
    sys.source(file.path("inst/app/R", f), envir = env)
  }
  env$user_db_file <- file.path(root, "user_dbs.yml")
  env$updateSelectInput <- function(...) invisible(NULL)
  env$append_log <- function(...) cat(sprintf(...), "\n", sep = "")
  taxonomy_dir <- env$localignr_taxonomy_ensure()
  fasta <- file.path(root, "test.faa")
  # Synthetic sequences assigned known species IDs solely for testing.
  seqs <- c("MKTAYIAKQRQISFVKSHFSRQDILDLWIYHTQGYFPQAKVEEFAEAFKVYQAYDEQKDKLEEV",
            "MALWMRLLPLLALLALWGPDPAAAFAKTLVQDEKGVVDFSATWCGPCKMIKPFFHSLSEKYSNV")
  ids <- c("sp|P00001|TEST_HUMAN", "sp|P00002|TEST_MOUSE")
  writeLines(c(paste0(">", ids[1], " test OS=Homo sapiens OX=9606"), seqs[1],
               paste0(">", ids[2], " test OS=Mus musculus OX=10090"), seqs[2]), fasta)
  state <- env$empty_registry_df()
  registry <- function(value) {
    if (missing(value)) return(state)
    state <<- value
  }
  # Include a conventional database to test backward compatibility.
  for (mode in c("legacy", "blast", "diamond")) {
    backend <- if (mode == "legacy") "blast" else mode
    input <- list(make_fasta = list(datapath = fasta), make_name = paste0("smoke_", mode),
                  make_type = "prot", make_backend = backend, make_outdir = root,
                  make_parse = TRUE, make_title = "Taxonomy smoke test", program = "blastp")
    env$run_makeseqdb_and_register(input, list(databases = list()), registry,
      function(...) character(), NULL, env$append_log,
      taxonomy = if (mode == "legacy") NULL else list(method = "uniprot", taxonomy_dir = taxonomy_dir))
  }
  saved <- env$load_user_dbs(env$user_db_file)
  stopifnot(nrow(saved) == 3L, sum(saved$has_taxonomy) == 2L,
            identical(saved$has_taxonomy, c(FALSE, TRUE, TRUE)),
            all(file.exists(saved$taxonomy_map_path[saved$has_taxonomy])),
            all(saved$taxonomy_dir[saved$has_taxonomy] == taxonomy_dir))
  # Test native TaxIDs for both entries, not only the mapping TSV.
  b <- saved[saved$name == "smoke_blast", , drop = FALSE]
  d <- saved[saved$name == "smoke_diamond", , drop = FALSE]
  blastdbcmd <- LocAlignR::localignr_find_tool("blastdbcmd", "LOCALIGN_BLASTDBCMD")
  diamond <- LocAlignR::localignr_find_tool("diamond", "LOCALIGN_DIAMOND")
  expected <- c("9606", "10090")
  for (i in seq_along(ids)) {
    result <- processx::run(blastdbcmd, c("-db", b$path, "-entry", sub("^sp\\|([^|]+)\\|.*$", "\\1", ids[i]), "-outfmt", "%T"))
    stopifnot(identical(trimws(result$stdout), expected[i]))
  }
  out <- file.path(root, "diamond_hits.tsv")
  processx::run(diamond, c("blastp", "--query", fasta, "--db", d$path,
     "--outfmt", "6", "qseqid", "sseqid", "staxids", "--max-target-seqs", "10", "--out", out))
  hits <- utils::read.delim(out, header = FALSE, colClasses = "character")
  for (i in seq_along(ids)) {
    # Use the accession to match either full or normalized output identifiers.
    acc <- sub("^sp\\|([^|]+)\\|.*$", "\\1", ids[i])
    self <- hits[grepl(acc, hits[[1]], fixed = TRUE) & grepl(acc, hits[[2]], fixed = TRUE), , drop = FALSE]
    stopifnot(nrow(self) >= 1L, all(self[[3]] == expected[i]))
  }
  cat("\nPASS: conventional BLAST, taxonomy BLAST, taxonomy DIAMOND, registry persistence and native TaxIDs.\n")
}
main()
