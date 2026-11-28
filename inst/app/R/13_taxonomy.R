# Shared NCBI taxonomy snapshots. No side effects when sourced.
localignr_taxonomy_root <- function() {
  file.path(tools::R_user_dir('LocAlignR', 'data'), 'taxonomy')
}

localignr_taxonomy_specs <- function() {
  list(
    list(url = 'https://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz',
         files = c('nodes.dmp', 'names.dmp', 'merged.dmp', 'delnodes.dmp')),
    list(url = 'https://ftp.ncbi.nih.gov/blast/db/taxdb.tar.gz',
         files = c('taxdb.btd', 'taxdb.bti', 'taxonomy4blast.sqlite3'))
  )
}

localignr_taxonomy_sha256 <- function(path) {
  digest::digest(file = path, algo = 'sha256', serialize = FALSE)
}

# A snapshot is valid only if every expected resource matches its recorded hash.
localignr_taxonomy_validate <- function(directory) {
  tryCatch({
    m <- jsonlite::read_json(file.path(directory, 'manifest.json'))
    expected <- unlist(lapply(localignr_taxonomy_specs(), `[[`, 'files'), use.names = FALSE)
    hashes <- unlist(m$files, use.names = TRUE)
    if (!identical(sort(names(hashes)), sort(expected))) return(FALSE)
    paths <- file.path(directory, expected)
    if (!all(file.exists(paths)) || any(dir.exists(paths))) return(FALSE)
    identical(unname(hashes[expected]), vapply(paths, localignr_taxonomy_sha256, '', USE.NAMES = FALSE))
  }, error = function(e) FALSE)
}

# Downloads are staged under the same filesystem and never replace a valid snapshot.
# A refresh creates a new snapshot; existing databases can retain their original one.
localignr_taxonomy_ensure <- function(root = localignr_taxonomy_root(), refresh = FALSE) {
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root <- normalizePath(root, winslash = '/', mustWork = TRUE)
  candidates <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  candidates <- sort(candidates[grepl('^ncbi-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{16}$', basename(candidates))], decreasing = TRUE)
  if (!refresh) for (p in candidates) {
    if (localignr_taxonomy_validate(p)) return(p)
  }
  stage <- tempfile('.taxonomy-stage-', tmpdir = root)
  if (!dir.create(stage)) stop('Cannot create taxonomy staging directory')
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  old <- options(timeout = max(600, getOption('timeout', 60)))
  on.exit(options(old), add = TRUE)
  specs <- localignr_taxonomy_specs()
  archives <- list()
  for (s in specs) {
    archive <- file.path(stage, basename(s$url))
    message('Downloading ', s$url)
    status <- utils::download.file(s$url, archive, mode = 'wb', method = 'libcurl')
    if (!identical(as.integer(status), 0L)) stop('Taxonomy download failed: ', s$url)
    checksum_path <- paste0(archive, '.md5')
    status <- utils::download.file(paste0(s$url, '.md5'), checksum_path, mode = 'wb', method = 'libcurl', quiet = TRUE)
    if (!identical(as.integer(status), 0L)) stop('Cannot download upstream checksum: ', s$url)
    line <- trimws(readLines(checksum_path, warn = FALSE)[1L])
    expected_md5 <- sub('^([a-fA-F0-9]{32}).*$', '\\1', line)
    if (!grepl('^[a-fA-F0-9]{32}$', expected_md5) || !identical(tolower(expected_md5), unname(tools::md5sum(archive)))) {
      stop('Taxonomy archive checksum mismatch: ', s$url)
    }
    members <- utils::untar(archive, list = TRUE, tar = 'internal')
    selected <- vapply(s$files, function(f) {
      matches <- members[members %in% c(f, paste0('./', f))]
      if (length(matches) != 1L) stop('Missing or ambiguous archive member: ', f)
      matches
    }, '')
    utils::untar(archive, files = unname(selected), exdir = stage, tar = 'internal')
    paths <- file.path(stage, s$files)
    if (!all(file.exists(paths)) || any(dir.exists(paths))) stop('Incomplete taxonomy extraction')
    if (any(file.info(paths[!s$files %in% c('merged.dmp', 'delnodes.dmp')])$size <= 0)) stop('Empty taxonomy resource')
    archives[[basename(s$url)]] <- list(url = s$url, md5 = tolower(expected_md5), sha256 = localignr_taxonomy_sha256(archive))
    unlink(c(archive, checksum_path))
  }
  files <- unlist(lapply(specs, `[[`, 'files'), use.names = FALSE)
  hashes <- setNames(vapply(file.path(stage, files), localignr_taxonomy_sha256, '', USE.NAMES = FALSE), files)
  timestamp <- format(Sys.time(), '%Y%m%dT%H%M%SZ', tz = 'UTC')
  fingerprint <- digest::digest(hashes, algo = 'sha256')
  destination <- file.path(root, paste0('ncbi-', timestamp, '-', substr(fingerprint, 1L, 16L)))
  jsonlite::write_json(list(provider = 'NCBI', downloaded_utc = timestamp, archives = archives, files = as.list(hashes)),
                       file.path(stage, 'manifest.json'), auto_unbox = TRUE, pretty = TRUE)
  if (!localignr_taxonomy_validate(stage)) stop('Staged taxonomy validation failed')
  if (dir.exists(destination) && localignr_taxonomy_validate(destination)) return(destination)
  if (!file.rename(stage, destination)) stop('Could not publish taxonomy snapshot')
  destination
}
