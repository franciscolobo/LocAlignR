# Native taxonomy search filters. No network access or side effects on source().
localignr_taxonomy_filter <- function(mode = "none", ids = "") {
  if (is.null(mode)) mode <- "none"
  if (length(mode) != 1L || is.na(mode) || !mode %in% c("none", "include", "exclude"))
    stop("Invalid taxonomy filter mode.", call. = FALSE)
  if (mode == "none") return(NULL)
  if (!length(ids) || anyNA(ids)) stop("Provide at least one NCBI TaxID.", call. = FALSE)
  raw <- trimws(paste(ids, collapse = ","))
  if (!grepl("^[1-9][0-9]*([,[:space:]]+[1-9][0-9]*)*$", raw))
    stop("Enter positive integer TaxIDs separated by commas or whitespace.", call. = FALSE)
  list(mode = mode, ids = unique(strsplit(raw, "[,[:space:]]+")[[1L]]))
}

localignr_taxonomy_search_config <- function(filter, db_res) {
  if (is.null(filter)) return(NULL)
  filter <- localignr_taxonomy_filter(filter$mode, filter$ids)
  if (is.null(filter)) return(NULL)
  if (isTRUE(db_res$remote) || !isTRUE(db_res$has_taxonomy))
    stop("Taxonomy filtering requires a taxonomy-aware local database. Choose a compatible database or turn filtering off.", call. = FALSE)
  directory <- db_res$taxonomy_dir
  if (length(directory) != 1L || is.na(directory) || !nzchar(directory) ||
      !localignr_taxonomy_validate(directory))
    stop("The database's taxonomy snapshot is missing or invalid. Restore it before searching.", call. = FALSE)
  list(mode = filter$mode,
       ids = unique(localignr_taxonomy_resolve_ids(filter$ids, directory)),
       snapshot = db_res$taxonomy_snapshot,
       directory = normalizePath(directory, winslash = "/", mustWork = TRUE))
}

localignr_taxonomy_search_args <- function(filter, engine, remote = FALSE) {
  if (is.null(filter)) return(character())
  filter <- localignr_taxonomy_filter(filter$mode, filter$ids)
  if (is.null(filter)) return(character())
  if (isTRUE(remote)) stop("Remote taxonomy filtering is not supported.", call. = FALSE)
  engine <- match.arg(engine, c("blast", "diamond"))
  flag <- if (engine == "blast") {
    if (filter$mode == "include") "-taxids" else "-negative_taxids"
  } else {
    if (filter$mode == "include") "--taxonlist" else "--taxon-exclude"
  }
  c(flag, paste(filter$ids, collapse = ","))
}

localignr_taxonomy_blast_env <- function(filter) {
  if (is.null(filter)) return(NULL)
  directory <- filter$directory
  if (length(directory) != 1L || is.na(directory) || !nzchar(directory) ||
      !file.exists(file.path(directory, "taxonomy4blast.sqlite3")))
    stop("BLAST requires the database's taxonomy4blast.sqlite3 snapshot.", call. = FALSE)
  paths <- c(directory, Sys.getenv("BLASTDB", unset = ""))
  c("current", BLASTDB = paste(paths[nzchar(paths)], collapse = .Platform$path.sep))
}
