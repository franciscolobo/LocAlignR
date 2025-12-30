# R/01_metadata.R

load_subject_meta <- function(tsv_path, csv_path) {
  path <- if (file.exists(tsv_path)) tsv_path else if (file.exists(csv_path)) csv_path else NA_character_

  if (is.na(path)) {
    logf("[META] No metadata file found")
    out <- data.frame(id = character(), stringsAsFactors = FALSE, check.names = FALSE)
    attr(out, "meta_path") <- NA_character_
    return(out)
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

  if (!length(idx)) {
    logf("[META] ERROR: No 'id' column")
    df$id <- character(nrow(df))
  } else if (n0[idx] != "id") {
    names(df)[idx] <- "id"
  }

  df <- dplyr::mutate(df, dplyr::across(dplyr::everything(), as.character))
  attr(df, "meta_path") <- normalizePath(path, winslash = "/")
  logf("[META] Rows: %d | Cols: %d", nrow(df), ncol(df))

  df
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
