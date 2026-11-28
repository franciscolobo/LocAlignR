# Offline lineage lookup. Cache one immutable snapshot per Shiny session.
localignr_taxonomy_ranks <- c('superkingdom', 'domain', 'kingdom', 'phylum',
                             'class', 'order', 'family', 'genus', 'species')

localignr_taxonomy_read_chunks <- function(path, parse) {
  con <- file(path, 'rt'); on.exit(close(con))
  chunks <- list()
  repeat {
    lines <- readLines(con, n = 50000L, warn = FALSE)
    if (!length(lines)) break
    chunks[[length(chunks) + 1L]] <- parse(lines)
  }
  do.call(rbind, chunks)
}

localignr_taxonomy_index <- function(directory) {
  nodes <- localignr_taxonomy_read_chunks(file.path(directory, 'nodes.dmp'), function(x) {
    p <- strsplit(x, '\t|\t', fixed = TRUE)
    data.frame(id = vapply(p, `[`, '', 1L), parent = vapply(p, `[`, '', 2L),
               rank = vapply(p, `[`, '', 3L), stringsAsFactors = FALSE)
  })
  names <- localignr_taxonomy_read_chunks(file.path(directory, 'names.dmp'), function(x) {
    x <- x[endsWith(x, '\t|\tscientific name\t|')]
    p <- strsplit(x, '\t|\t', fixed = TRUE)
    data.frame(id = vapply(p, `[`, '', 1L), name = vapply(p, `[`, '', 2L), stringsAsFactors = FALSE)
  })
  merged <- localignr_taxonomy_read_chunks(file.path(directory, 'merged.dmp'), function(x) {
    p <- strsplit(x, '\t|\t', fixed = TRUE)
    # Strip the terminal delimiter independently (literal pipe).
    data.frame(old = vapply(p, `[`, '', 1L),
               new = trimws(sub('|', '', vapply(p, `[`, '', 2L), fixed = TRUE)), stringsAsFactors = FALSE)
  })
  nodes$name <- names$name[match(nodes$id, names$id)]
  nodes$parent_index <- match(nodes$parent, nodes$id)
  list(nodes = nodes, merged = merged)
}

localignr_taxonomy_lineages <- function(ids, index) {
  ids <- as.character(ids)
  unique_ids <- unique(ids)
  n <- index$nodes
  # Resolve obsolete IDs without failing the entire result set.
  resolved <- unique_ids
  for (i in seq_len(100L)) {
    next_id <- index$merged$new[match(resolved, index$merged$old)]
    ok <- !is.na(next_id)
    if (!any(ok)) break
    resolved[ok] <- next_id[ok]
  }
  columns <- c('taxon_id', 'taxon_name', paste0('taxon_', localignr_taxonomy_ranks), 'taxon_lineage')
  out <- matrix(NA_character_, nrow = length(unique_ids), ncol = length(columns), dimnames = list(NULL, columns))
  starts <- match(resolved, n$id)
  for (i in which(!is.na(starts))) {
    j <- starts[i]; path <- integer()
    while (!is.na(j) && !j %in% path) {
      path <- c(path, j)
      if (identical(n$parent_index[j], j)) break
      j <- n$parent_index[j]
    }
    out[i, 'taxon_id'] <- n$id[starts[i]]
    out[i, 'taxon_name'] <- n$name[starts[i]]
    for (rank in localignr_taxonomy_ranks) {
      k <- path[match(rank, n$rank[path])]
      if (!is.na(k)) out[i, paste0('taxon_', rank)] <- n$name[k]
    }
    out[i, 'taxon_lineage'] <- paste(rev(stats::na.omit(n$name[path])), collapse = '; ')
  }
  as.data.frame(out[match(ids, unique_ids), , drop = FALSE], stringsAsFactors = FALSE)
}

localignr_taxonomy_find <- function(query, index, limit = 50L) {
  query <- trimws(query)
  n <- index$nodes
  if (!nzchar(query)) return(n[FALSE, c('id','name','rank')])
  if (grepl('^[0-9]+$', query)) {
    resolved <- localignr_taxonomy_lineages(query, index)$taxon_id
    return(n[which(n$id == resolved), c('id','name','rank'), drop = FALSE])
  }
  hits <- which(grepl(tolower(query), tolower(n$name), fixed = TRUE))
  # Exact names precede partial matches; ambiguous names remain separate.
  hits <- hits[order(tolower(n$name[hits]) != tolower(query), n$name[hits])]
  n[head(hits, limit), c('id','name','rank'), drop = FALSE]
}

# Metadata for actual hits only. Mapping takes precedence over header TaxIDs.
localignr_taxonomy_annotate <- function(hits, meta, mapping, index) {
  hits <- unique(as.character(hits))
  out <- if (nrow(meta)) meta[localignr_match_subjects(hits, meta$id), , drop = FALSE] else
    data.frame(id = hits, stringsAsFactors = FALSE)
  out$id <- hits
  ids <- if ('taxid' %in% names(out)) as.character(out$taxid) else rep(NA_character_, length(hits))
  if (!is.null(mapping)) {
    mapped <- mapping$taxid[localignr_match_subjects(hits, mapping$id)]
    ids[!is.na(mapped)] <- mapped[!is.na(mapped)]
  }
  if (is.null(index)) return(out)
  cbind(out, localignr_taxonomy_lineages(ids, index))
}
