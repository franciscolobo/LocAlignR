# Taxonomy-aware database construction. No downloads or writes on source().
# The canonical mapping uses exact FASTA identifiers (first whitespace token).
localignr_taxonomy_fasta_headers <- function(path) {
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, "rt") else file(path, "rt")
  on.exit(close(con))
  chunks <- list()
  repeat {
    lines <- readLines(con, n = 50000L, warn = FALSE)
    if (!length(lines)) break
    h <- lines[startsWith(lines, ">")]
    if (length(h)) chunks[[length(chunks) + 1L]] <- substring(h, 2L)
  }
  headers <- unlist(chunks, use.names = FALSE)
  if (!length(headers)) stop("No FASTA headers found.")
  ids <- sub("[[:space:]].*$", "", headers)
  if (any(!nzchar(ids)) || anyDuplicated(ids)) stop("FASTA identifiers must be nonempty and unique.")
  data.frame(id = ids, header = headers, stringsAsFactors = FALSE)
}

localignr_taxonomy_check_ids <- function(taxids) {
  taxids <- trimws(as.character(taxids))
  if (anyNA(taxids) || any(!grepl("^[1-9][0-9]*$", taxids))) {
    stop("Every sequence must have a positive integer TaxID.")
  }
  taxids
}

localignr_taxonomy_read_map <- function(path) {
  x <- utils::read.delim(path, header = TRUE, sep = "\t", quote = "", comment.char = "",
                         colClasses = "character", check.names = FALSE, na.strings = NULL, row.names = NULL, fill = FALSE)
  if (!identical(names(x), c("id", "taxid"))) stop("Mapping TSV must have exactly two columns: id and taxid.")
  if (anyNA(x$id) || any(!nzchar(x$id)) || anyDuplicated(x$id)) stop("Mapping identifiers must be nonempty and unique.")
  x$taxid <- localignr_taxonomy_check_ids(x$taxid)
  x
}

localignr_taxonomy_resolve_ids <- function(taxids, taxonomy_dir) {
  # Use the same NCBI snapshot that will be supplied to the indexer.
  read_merged <- function(name) {
    path <- file.path(taxonomy_dir, name)
    lines <- readLines(path, warn = FALSE)
    parts <- strsplit(lines, "|", fixed = TRUE)
    data.frame(old = vapply(parts, function(x) trimws(x[1L]), ""),
               new = vapply(parts, function(x) trimws(x[2L]), ""), stringsAsFactors = FALSE)
  }
  merged <- read_merged("merged.dmp")
  unique_ids <- unique(taxids)
  resolved <- unique_ids
  # Merged IDs are obsolete; follow any chains before validating current IDs.
  for (i in seq_len(100L)) {
    replacements <- merged$new[match(resolved, merged$old)]
    replace <- !is.na(replacements)
    if (!any(replace)) break
    resolved[replace] <- replacements[replace]
  }
  if (any(resolved %in% merged$old)) stop("Could not resolve obsolete taxonomy IDs.")
  # Stream nodes.dmp to bound memory use even for the full NCBI taxonomy.
  pending <- unique(resolved)
  con <- file(file.path(taxonomy_dir, "nodes.dmp"), "rt")
  on.exit(close(con))
  while (length(pending)) {
    lines <- readLines(con, n = 100000L, warn = FALSE)
    if (!length(lines)) break
    nodes <- trimws(sub("\\|.*$", "", lines))
    pending <- pending[!pending %in% nodes]
  }
  if (length(pending)) stop("Unknown or deleted TaxID(s): ", paste(head(pending, 10L), collapse = ", "))
  resolved[match(taxids, unique_ids)]
}

localignr_taxonomy_prepare_build <- function(fasta, backend, directory,
                                            method = c("uniprot", "single", "mapping"),
                                            taxid = NULL, mapping_path = NULL,
                                            taxonomy_dir = NULL) {
  method <- match.arg(method)
  backend <- match.arg(backend, c("blast", "diamond"))
  h <- localignr_taxonomy_fasta_headers(fasta)
  if (method == "uniprot") {
    ok <- grepl("^(sp|tr)\\|[^|[:space:]]+\\|[^|[:space:]]+$", h$id) &
          grepl("[[:space:]]OX=[1-9][0-9]*([[:space:]]|$)", h$header)
    if (!all(ok)) stop("All FASTA headers must be UniProt headers with an OX= TaxID.")
    taxids <- sub("^.*[[:space:]]OX=([0-9]+)([[:space:]].*)?$", "\\1", h$header)
  } else if (method == "single") {
    if (length(taxid) != 1L) stop("Provide exactly one taxonomy ID.")
    taxids <- rep(taxid, nrow(h))
  } else {
    if (length(mapping_path) != 1L || !file.exists(mapping_path)) stop("Choose a mapping TSV.")
    m <- localignr_taxonomy_read_map(mapping_path)
    if (!setequal(m$id, h$id)) stop("Mapping identifiers must match all FASTA identifiers exactly (no missing or extra IDs).")
    taxids <- m$taxid[match(h$id, m$id)]
  }
  taxids <- localignr_taxonomy_check_ids(taxids)
  if (is.null(taxonomy_dir)) taxonomy_dir <- localignr_taxonomy_ensure()
  else if (!localignr_taxonomy_validate(taxonomy_dir)) stop("Invalid taxonomy snapshot.")
  taxonomy_dir <- normalizePath(taxonomy_dir, winslash = "/", mustWork = TRUE)
  taxids <- localignr_taxonomy_resolve_ids(taxids, taxonomy_dir)
  mapping <- data.frame(id = h$id, taxid = taxids, stringsAsFactors = FALSE)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(directory)) stop("Cannot create mapping directory.")
  canonical <- file.path(directory, "sequence_taxid.tsv")
  utils::write.table(mapping, canonical, sep = "\t", quote = FALSE, row.names = FALSE)
  if (backend == "blast") {
    native <- file.path(directory, "blast_taxid_map.tsv")
    utils::write.table(mapping, native, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    args <- c("-parse_seqids", "-blastdb_version", "5", "-taxid_map", native)
  } else {
    native <- file.path(directory, "diamond_taxid_map.tsv")
    # Match literal identifiers to avoid accession normalization collisions.
    diamond <- data.frame(accession = mapping$id, accession.version = mapping$id,
                          taxid = mapping$taxid, gi = "0", stringsAsFactors = FALSE)
    utils::write.table(diamond, native, sep = "\t", quote = FALSE, row.names = FALSE)
    args <- c("--no-parse-seqids", "--taxonmap", native,
              "--taxonnodes", file.path(taxonomy_dir, "nodes.dmp"),
              "--taxonnames", file.path(taxonomy_dir, "names.dmp"))
  }
  list(args = args, mapping = mapping, map_path = canonical, native_map_path = native,
       taxonomy_dir = taxonomy_dir, taxonomy_snapshot = basename(taxonomy_dir))
}

# DIAMOND 2.2.8 makedb reports this count in its build summary. Require it
# rather than treating a successful exit code as proof of taxonomy coverage.
localignr_taxonomy_validate_diamond_log <- function(stdout, stderr, expected) {
  lines <- unlist(strsplit(c(stdout, stderr), "\n", fixed = TRUE), use.names = FALSE)
  pattern <- "^[[:space:]]*Database sequences mapped to taxid[[:space:]:]+([0-9]+)[[:space:]]*$"
  rows <- grep(pattern, lines, value = TRUE)
  counts <- unique(as.numeric(sub(pattern, "\\1", rows)))
  if (length(counts) != 1L || is.na(counts) || counts != expected) {
    stop("DIAMOND did not confirm complete taxonomy mapping (expected ", expected,
         " sequences). Inspect the makedb log.")
  }
  invisible(TRUE)
}
