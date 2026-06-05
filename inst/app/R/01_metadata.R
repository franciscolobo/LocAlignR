# R/01_metadata.R

empty_subject_meta <- function(meta_path = NA_character_) {
  out <- data.frame(id = character(), stringsAsFactors = FALSE, check.names = FALSE)
  attr(out, "meta_path") <- meta_path
  out
}

metadata_cache_key <- function(db_name, registry) {
  path <- metadata_path_for_db(db_name, registry)
  
  if (is.na(path) || !nzchar(path)) {
    return(paste0("NO_METADATA::", db_name))
  }
  
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

load_subject_meta <- function(path = NA_character_) {
  if (is.null(path) || !length(path) || is.na(path) || !nzchar(path) || !file.exists(path)) {
    logf("[META] No database-specific metadata file found")
    return(empty_subject_meta())
  }
  
  logf("[META] Reading: %s", normalizePath(path, winslash = "/"))
  
  df <- if (grepl("\\.tsv$", path, ignore.case = TRUE)) {
    read.delim(
      path, sep = "\t", header = TRUE, quote = "", comment.char = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  } else {
    read.csv(
      path, header = TRUE, quote = "", comment.char = "",
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  
  n0 <- names(df)
  idx <- which(tolower(n0) == "id")[1]
  
  if (!length(idx) || is.na(idx)) {
    logf("[META] ERROR: No 'id' column in metadata file")
    df$id <- character(nrow(df))
  } else if (n0[idx] != "id") {
    names(df)[idx] <- "id"
  }
  
  df <- dplyr::mutate(df, dplyr::across(dplyr::everything(), as.character))
  
  attr(df, "meta_path") <- normalizePath(path, winslash = "/")
  logf("[META] Rows: %d | Cols: %d", nrow(df), ncol(df))
  
  df
}

metadata_path_for_db <- function(db_name, registry) {
  row <- registry[match(db_name, registry$name), , drop = FALSE]
  
  if (!nrow(row)) {
    return(NA_character_)
  }
  
  if (!"metadata_path" %in% names(row)) {
    return(NA_character_)
  }
  
  path <- row$metadata_path[1]
  
  if (is.na(path) || !nzchar(path)) {
    return(NA_character_)
  }
  
  path
}

load_subject_meta_for_db <- function(db_name, registry) {
  path <- metadata_path_for_db(db_name, registry)
  load_subject_meta(path)
}

canon_id <- function(x) {
  x <- as.character(x)
  x <- enc2utf8(x)
  x <- trimws(x)
  x <- sub("\\s.*$", "", x)
  x <- sub("^.*\\|", "", x)
  x <- sub("\\.\\d+$", "", x)
  x
}

build_tt_row <- function(dfrow) {
  if (!nrow(dfrow)) return("No metadata")
  
  vals <- as.list(dfrow[1, , drop = FALSE])
  nms <- names(vals)
  
  vchr <- vapply(vals, function(v) if (length(v)) as.character(v)[1] else "", character(1))
  keep <- nms[!is.na(vchr) & nzchar(vchr)]
  
  if (!length(keep)) return("No metadata")
  
  paste(
    sprintf("<b>%s</b>: %s", htmltools::htmlEscape(keep), htmltools::htmlEscape(vchr[keep])),
    collapse = "<br>"
  )
}

build_text_row <- function(dfrow) {
  if (!nrow(dfrow)) return("No metadata")
  
  vals <- as.list(dfrow[1, , drop = FALSE])
  nms <- names(vals)
  
  vchr <- vapply(vals, function(v) if (length(v)) as.character(v)[1] else "", character(1))
  keep <- nms[!is.na(vchr) & nzchar(vchr)]
  
  if (!length(keep)) return("No metadata")
  
  paste(sprintf("%s: %s", keep, vchr[keep]), collapse = "\n")
}