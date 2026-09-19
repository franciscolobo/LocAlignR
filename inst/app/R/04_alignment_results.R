# inst/app/R/04_alignment_results.R
#
# Aligner-agnostic result handling: input validation, query materialization,
# BLAST-XML parsing (used by both BLAST and DIAMOND, since DIAMOND's
# --outfmt 5 emits the same schema), results-table rendering, alignment
# display, and report export (HTML + Excel).

validate_alignment_inputs <- function(input, use_upload) {
  if (identical(input$input_mode, "upload")) {
    shiny::validate(shiny::need(isTRUE(use_upload), "Please choose a FASTA file."))
  } else {
    shiny::validate(shiny::need(nzchar(trimws(input$query)), "Please paste a sequence."))
  }
}

# Backward compatibility
validate_blast_inputs <- validate_alignment_inputs

make_query_signature <- function(input, use_upload) {
  if (isTRUE(use_upload)) {
    paste0("file:", digest::digest(file = input$fasta$datapath, algo = "md5"))
  } else {
    trimws(input$query)
  }
}

materialize_query_fasta <- function(input, use_upload) {
  if (isTRUE(use_upload)) {
    path <- normalizePath(input$fasta$datapath)
    list(
      path = path,
      cleanup = function() {
        invisible(NULL)
      }
    )
  } else {
    tmp <- tempfile(fileext = ".fa")
    q <- trimws(input$query)

    # Ensure a FASTA header exists
    if (startsWith(q, ">")) {
      writeLines(q, tmp)
    } else {
      writeLines(paste0(">Query\n", q), tmp)
    }

    list(
      path = tmp,
      cleanup = function() {
        if (file.exists(tmp)) unlink(tmp)
        invisible(NULL)
      }
    )
  }
}

parse_blast_xml_to_df <- function(xml_doc) {
  # Always return a data.frame with these columns, even if there are no hits.
  empty_df <- function() {
    data.frame(
      query_ID = character(),
      hit_ID = character(),
      hsp_q_begin = character(),
      hsp_q_end = character(),
      hit_length = character(),
      query_fraction = character(),
      bitscore = character(),
      eval = character(),
      stringsAsFactors = FALSE
    )
  }

  results <- XML::xpathApply(xml_doc, "//Iteration", function(row) {
    query_ID     <- XML::getNodeSet(row, "Iteration_query-def") %>% sapply(XML::xmlValue)
    query_length <- XML::getNodeSet(row, "Iteration_query-len") %>% sapply(XML::xmlValue)
    hit_ID       <- XML::getNodeSet(row, "Iteration_hits//Hit//Hit_id") %>% sapply(XML::xmlValue)

    # No hits for this query
    if (!length(hit_ID)) return(NULL)

    bitscore    <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_bit-score") %>% sapply(XML::xmlValue)
    eval        <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_evalue") %>% sapply(XML::xmlValue)
    hsp_q_begin <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(XML::xmlValue)
    hsp_q_end   <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to") %>% sapply(XML::xmlValue)

    # Note: kept identical to current behavior.
    hsp_s_begin <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(XML::xmlValue)
    hsp_s_end   <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to") %>% sapply(XML::xmlValue)

    eval <- suppressWarnings(as.numeric(eval))
    eval <- signif(eval, digits = 3)

    qlen <- suppressWarnings(as.numeric(query_length))
    hit_length <- suppressWarnings(as.numeric(hsp_q_end) - as.numeric(hsp_q_begin) + 1)

    qfrac <- ifelse(is.finite(hit_length / qlen), round(hit_length / qlen, 2), NA_real_)

    as.data.frame(
      cbind(
        query_ID,
        hit_ID,
        hsp_q_begin,
        hsp_q_end,
        hit_length,
        query_fraction = qfrac,
        bitscore,
        eval
      ),
      stringsAsFactors = FALSE
    )
  })

  # Drop NULL entries (Iterations with no hits)
  results <- Filter(Negate(is.null), results)

  if (!length(results)) return(empty_df())

  out <- plyr::rbind.fill(results)
  if (is.null(out)) empty_df() else out
}

parse_alignment_xml_to_df <- function(xml_doc, aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")

  switch(
    aligner,
    "BLAST" = parse_blast_xml_to_df(xml_doc),
    "DIAMOND" = parse_blast_xml_to_df(xml_doc),
    stop("Unsupported aligner: ", aligner)
  )
}

.render_blast_results_dt_impl <- function(df, subject_meta) {
  df_join   <- dplyr::mutate(df, .join = canon_id(hit_ID))
  meta_join <- dplyr::mutate(subject_meta, .join = canon_id(id))

  merged <- suppressMessages(dplyr::left_join(df_join, meta_join, by = ".join"))

  right_cols <- setdiff(names(merged), names(df_join))
  meta_cols  <- setdiff(right_cols, c("id", ".join"))

  tt <- if (nrow(merged)) {
    vapply(seq_len(nrow(merged)), function(i) {
      if (length(meta_cols)) build_tt_row(merged[i, meta_cols, drop = FALSE]) else "No metadata"
    }, character(1))
  } else {
    character(0)
  }

  display <- df

  if (length(tt)) {
    display$hit_ID <- sprintf(
      '<span data-toggle="tooltip" data-html="true" title="%s">%s</span>',
      tt, htmltools::htmlEscape(df$hit_ID)
    )
  } else {
    display$hit_ID <- htmltools::htmlEscape(df$hit_ID)
  }

  display <- display |>
    dplyr::mutate(
      hsp_q_begin    = suppressWarnings(as.integer(hsp_q_begin)),
      hsp_q_end      = suppressWarnings(as.integer(hsp_q_end)),
      hit_length     = suppressWarnings(as.integer(hit_length)),
      query_fraction = suppressWarnings(as.numeric(query_fraction)),
      pct_cov        = round(query_fraction * 100, 2),
      bitscore       = suppressWarnings(as.numeric(bitscore)),
      eval           = suppressWarnings(signif(as.numeric(eval), digits = 3))
    )

  cols <- c(
    query_ID    = "Query ID",
    hsp_q_begin = "Query begin",
    hsp_q_end   = "Query end",
    hit_ID      = "Hit ID",
    hit_length  = "Hit length",
    pct_cov     = "%cov",
    bitscore    = "Bit Score",
    eval        = "e-value"
  )

  display <- display[names(cols)]

  DT::datatable(
    display,
    colnames = unname(cols),
    escape = FALSE,
    selection = "single",
    filter = "top",
    options = list(
      pageLength = 10,
      searchHighlight = TRUE,
      drawCallback = DT::JS(
        "$('body').tooltip({selector:'[data-toggle=\"tooltip\"]', container:'body', html:true});"
      )
    )
  ) |>
    DT::formatRound("pct_cov", digits = 2)
}

render_alignment_results_dt <- function(df, subject_meta) {
  .render_blast_results_dt_impl(df = df, subject_meta = subject_meta)
}

render_blast_results_dt <- function(df, subject_meta) {
  .render_blast_results_dt_impl(df = df, subject_meta = subject_meta)
}

render_clicked_summary_table <- function(row, subject_meta) {
  idraw <- as.character(row$hit_ID)
  key   <- canon_id(idraw)

  meta_rows <- subject_meta[canon_id(subject_meta$id) == key, , drop = FALSE]
  meta_cols <- setdiff(names(subject_meta), "id")

  tt <- if (nrow(meta_rows)) build_tt_row(meta_rows[, meta_cols, drop = FALSE]) else "No metadata"

  id_disp <- sprintf(
    '<span data-toggle="tooltip" data-html="true" title="%s">%s</span>',
    tt, htmltools::htmlEscape(idraw)
  )

  data.frame(
    Field = c("Query ID", "Hit ID", "Hit begin", "Hit end", "Hit length", "Query aln fraction", "Bit Score", "e-value"),
    Value = c(
      as.character(row$query_ID),
      id_disp,
      as.character(row$hsp_q_begin),
      as.character(row$hsp_q_end),
      as.character(row$hit_length),
      as.character(row$query_fraction),
      as.character(row$bitscore),
      as.character(row$eval)
    ),
    stringsAsFactors = FALSE
  )
}

render_alignment_for_row <- function(xml_doc, row_index, width = 40) {
  hsps <- XML::getNodeSet(xml_doc, "//Hsp")

  shiny::validate(
    shiny::need(length(hsps) >= row_index, "Selected alignment was not found in the XML.")
  )

  hsp <- hsps[[row_index]]

  get_text <- function(node, tag) {
    x <- XML::getNodeSet(node, tag)
    if (!length(x)) return("")
    as.character(XML::xmlValue(x[[1]]))
  }

  get_int <- function(node, tag) {
    suppressWarnings(as.integer(get_text(node, tag)))
  }

  qseq_local <- get_text(hsp, "Hsp_qseq")
  mid_local  <- get_text(hsp, "Hsp_midline")
  hseq_local <- get_text(hsp, "Hsp_hseq")

  q_from_local <- get_int(hsp, "Hsp_query-from")
  q_to_local   <- get_int(hsp, "Hsp_query-to")
  h_from_local <- get_int(hsp, "Hsp_hit-from")
  h_to_local   <- get_int(hsp, "Hsp_hit-to")

  wrap_alignment_with_coords(
    qseq   = qseq_local,
    mid    = mid_local,
    hseq   = hseq_local,
    q_from = q_from_local,
    q_to   = q_to_local,
    h_from = h_from_local,
    h_to   = h_to_local,
    width  = width
  )
}

align_strings <- function(xml_doc, width = 40) {
  al <- XML::xpathApply(xml_doc, "//Iteration", function(row) {
    top <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_qseq") %>% sapply(XML::xmlValue)
    mid <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_midline") %>% sapply(XML::xmlValue)
    bot <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hseq") %>% sapply(XML::xmlValue)
    rbind(top, mid, bot)
  })

  if (!length(al)) return(character())

  ax <- do.call("cbind", al)

  vapply(seq_len(ncol(ax)), function(i) {
    wrap_alignment(ax[1, i], ax[2, i], ax[3, i], width = width)
  }, character(1))
}

build_and_save_alignment_html_report <- function(file, xml_doc, df, subject_meta) {
  df_join   <- dplyr::mutate(df, .join = canon_id(hit_ID))
  meta_join <- dplyr::mutate(subject_meta, .join = canon_id(id))
  merged    <- suppressMessages(dplyr::left_join(df_join, meta_join, by = ".join"))

  right_cols <- setdiff(names(merged), names(df_join))
  meta_cols  <- setdiff(right_cols, c("id", ".join"))

  al_vec <- align_strings(xml_doc, width = 40)
  if (length(al_vec) != nrow(df)) {
    length(al_vec) <- nrow(df)
    al_vec[is.na(al_vec)] <- ""
  }

  tip_vec <- vapply(seq_len(nrow(merged)), function(i) {
    meta_txt <- if (length(meta_cols)) build_text_row(merged[i, meta_cols, drop = FALSE]) else "No metadata"
    paste(c("Metadata:", meta_txt, "", "Alignment:", al_vec[i] %||% ""), collapse = "\n")
  }, character(1))

  display <- df %>%
    dplyr::mutate(
      hsp_q_begin    = suppressWarnings(as.integer(hsp_q_begin)),
      hsp_q_end      = suppressWarnings(as.integer(hsp_q_end)),
      hit_length     = suppressWarnings(as.integer(hit_length)),
      query_fraction = suppressWarnings(as.numeric(query_fraction)),
      bitscore       = suppressWarnings(as.numeric(bitscore)),
      eval           = suppressWarnings(as.numeric(eval))
    )

  esc_tip <- htmltools::htmlEscape(tip_vec, attribute = TRUE)
  display$hit_ID <- sprintf(
    '<span class="tt" data-tip="%s">%s</span>',
    esc_tip, htmltools::htmlEscape(display$hit_ID)
  )

  cols <- c(
    query_ID       = "Query ID",
    hit_ID         = "Hit ID",
    hsp_q_begin    = "Hit begin",
    hsp_q_end      = "Hit end",
    hit_length     = "Hit length",
    query_fraction = "Query aln fraction",
    bitscore       = "Bit Score",
    eval           = "e-value"
  )
  display <- display[names(cols)]

  widget <- DT::datatable(
    display,
    colnames = unname(cols),
    escape = FALSE,
    selection = "none",
    filter = "top",
    options = list(pageLength = 20, searchHighlight = TRUE)
  ) %>% DT::formatRound("query_fraction", digits = 2)

  tooltip_css <- htmltools::tags$style(htmltools::HTML("
    .tt{position:relative; cursor:help;}
    .tt:hover::after{
      content: attr(data-tip);
      position:absolute; left:0; top:100%;
      z-index:9999;
      white-space: pre;
      font-family: 'Courier New', Courier, monospace;
      font-size: 12px;
      background:#111; color:#fff;
      padding:8px 10px; border-radius:4px;
      box-shadow:0 2px 8px rgba(0,0,0,.3);
      margin-top:6px; min-width:300px; max-width:70vw;
    }
    .tt:hover::before{
      content:''; position:absolute; left:10px; top:100%;
      border:6px solid transparent; border-bottom-color:#111; transform: translateY(-12px);
    }
  "))

  widget <- htmlwidgets::prependContent(widget, tooltip_css)
  htmlwidgets::saveWidget(widget, file, selfcontained = TRUE, title = "Alignment results")
}

# Backward compatibility
build_and_save_html_report <- build_and_save_alignment_html_report

#' Build and save the alignment results table as a formatted Excel workbook.
#'
#' Mirrors build_and_save_alignment_html_report()'s data assembly (same
#' metadata join via canon_id, same alignment-block reuse via align_strings()),
#' but writes a self-contained .xlsx instead of an HTML widget: core hit
#' columns, joined subject metadata columns, and a monospaced Alignment column
#' per row.
build_and_save_alignment_xlsx_report <- function(file, xml_doc, df, subject_meta) {
  df_join   <- dplyr::mutate(df, .join = canon_id(hit_ID))
  meta_join <- dplyr::mutate(subject_meta, .join = canon_id(id))
  merged    <- suppressMessages(dplyr::left_join(df_join, meta_join, by = ".join"))

  right_cols <- setdiff(names(merged), names(df_join))
  meta_cols  <- setdiff(right_cols, c("id", ".join"))

  al_vec <- align_strings(xml_doc, width = 60)
  if (length(al_vec) != nrow(df)) {
    length(al_vec) <- nrow(df)
    al_vec[is.na(al_vec)] <- ""
  }

  out <- df %>%
    dplyr::mutate(
      hsp_q_begin    = suppressWarnings(as.integer(hsp_q_begin)),
      hsp_q_end      = suppressWarnings(as.integer(hsp_q_end)),
      hit_length     = suppressWarnings(as.integer(hit_length)),
      query_fraction = suppressWarnings(as.numeric(query_fraction)),
      pct_cov        = round(query_fraction * 100, 2),
      bitscore       = suppressWarnings(as.numeric(bitscore)),
      eval           = suppressWarnings(as.numeric(eval))
    )

  core_cols <- c(
    query_ID    = "Query ID",
    hit_ID      = "Hit ID",
    hsp_q_begin = "Query begin",
    hsp_q_end   = "Query end",
    hit_length  = "Hit length",
    pct_cov     = "%cov",
    bitscore    = "Bit Score",
    eval        = "e-value"
  )

  out <- out[names(core_cols)]
  names(out) <- unname(core_cols)

  if (length(meta_cols)) {
    meta_block <- merged[meta_cols]
    names(meta_block) <- meta_cols
    out <- cbind(out, meta_block)
  }

  out$Alignment <- al_vec

  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Alignment results")

  openxlsx::writeDataTable(
    wb, "Alignment results",
    x = out,
    tableStyle = "TableStyleLight9",
    withFilter = TRUE
  )

  align_col <- which(names(out) == "Alignment")

  openxlsx::addStyle(
    wb, "Alignment results",
    style = openxlsx::createStyle(fontName = "Courier New", wrapText = TRUE, valign = "top"),
    rows = seq_len(nrow(out)) + 1,
    cols = align_col,
    gridExpand = TRUE
  )

  non_align_cols <- setdiff(seq_len(ncol(out)), align_col)
  openxlsx::setColWidths(wb, "Alignment results", cols = non_align_cols, widths = "auto")
  openxlsx::setColWidths(wb, "Alignment results", cols = align_col, widths = 80)

  openxlsx::freezePane(wb, "Alignment results", firstRow = TRUE)

  openxlsx::saveWorkbook(wb, file, overwrite = TRUE)
}
