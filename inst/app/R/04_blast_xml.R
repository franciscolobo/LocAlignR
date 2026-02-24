# R/04_blast_xml.R

validate_blast_inputs <- function(input, use_upload) {
  if (identical(input$input_mode, "upload")) {
    shiny::validate(shiny::need(isTRUE(use_upload), "Please choose a FASTA file."))
  } else {
    shiny::validate(shiny::need(nzchar(trimws(input$query)), "Please paste a sequence."))
  }
}

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
      cleanup = function() invisible(NULL)
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

run_blast_as_xml <- function(prog, query, db, eval, remote) {
  args <- c(
    "-query", query,
    "-db", db,
    "-evalue", as.character(eval),
    "-outfmt", "5",
    "-max_hsps", "1",
    "-max_target_seqs", "10"
  )

  if (isTRUE(remote)) {
    args <- c(args, "-remote")
  } else {
    threads <- as.character(max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
    args <- c(args, "-num_threads", threads)
  }
  # Conda-first tool discovery: prefer PATH, allow override via LOCALIGN_<PROG>
  prog_path <- LocAlignR::localignr_find_tool(prog, env_var = paste0("LOCALIGN_", toupper(prog)))

  # Validate early with a clear message for cross-platform installs
  validate(
    need(
      nzchar(prog_path),
      paste0(prog, " not found. Activate the conda environment (preferred) or set ", 
             paste0("LOCALIGN_", toupper(prog)), ".")
    )
  )

  res <- processx::run(prog_path, args, error_on_status = FALSE, timeout = 600, echo = FALSE)


  shiny::validate(
    shiny::need(res$status == 0, paste("BLAST failed:", res$stderr)),
    shiny::need(nzchar(res$stdout), "BLAST returned no output.")
  )

  XML::xmlParse(res$stdout, asText = TRUE, useInternalNodes = TRUE)
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

    # Note: kept identical to your current code (even though variable names suggest "subject").
    hsp_s_begin <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(XML::xmlValue)
    hsp_s_end   <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to") %>% sapply(XML::xmlValue)

    eval <- suppressWarnings(as.numeric(eval))
    eval <- signif(eval, digits = 3)

    qlen <- suppressWarnings(as.numeric(query_length))
    hit_length <- suppressWarnings(as.numeric(hsp_q_end) - as.numeric(hsp_q_begin) + 1)

    qfrac <- ifelse(is.finite(hit_length / qlen), round(hit_length / qlen, 2), NA_real_)

    as.data.frame(
      cbind(query_ID, hit_ID, hsp_q_begin, hsp_q_end, hit_length,
            query_fraction = qfrac, bitscore, eval),
      stringsAsFactors = FALSE
    )
  })

  # Drop NULL entries (Iterations with no hits)
  results <- Filter(Negate(is.null), results)

  if (!length(results)) return(empty_df())

  out <- plyr::rbind.fill(results)
  if (is.null(out)) empty_df() else out
}

render_blast_results_dt <- function(df, subject_meta) {
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
  # sequences per HSP
  al <- XML::xpathApply(xml_doc, "//Iteration", function(row) {
    top <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_qseq")    %>% sapply(XML::xmlValue)
    mid <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_midline") %>% sapply(XML::xmlValue)
    bot <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hseq")    %>% sapply(XML::xmlValue)
    rbind(top, mid, bot)
  })
  ax <- do.call("cbind", al)

  # coordinates per HSP
  pos <- XML::xpathApply(xml_doc, "//Iteration", function(row) {
    qf <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(XML::xmlValue)
    qt <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to")   %>% sapply(XML::xmlValue)
    hf <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hit-from")   %>% sapply(XML::xmlValue)
    ht <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hit-to")     %>% sapply(XML::xmlValue)
    rbind(qf, qt, hf, ht)
  })
  px <- do.call("cbind", pos)

  i <- row_index

  wrap_alignment_with_coords(
    qseq   = ax[1, i],
    mid    = ax[2, i],
    hseq   = ax[3, i],
    q_from = as.integer(px[1, i]),
    q_to   = as.integer(px[2, i]),
    h_from = as.integer(px[3, i]),
    h_to   = as.integer(px[4, i]),
    width  = width
  )
}

align_strings <- function(xml_doc, width = 40) {
  al <- XML::xpathApply(xml_doc, "//Iteration", function(row) {
    top <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_qseq")    %>% sapply(XML::xmlValue)
    mid <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_midline") %>% sapply(XML::xmlValue)
    bot <- XML::getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hseq")    %>% sapply(XML::xmlValue)
    rbind(top, mid, bot)
  })

  if (!length(al)) return(character())

  ax <- do.call("cbind", al)

  vapply(seq_len(ncol(ax)), function(i) {
    wrap_alignment(ax[1, i], ax[2, i], ax[3, i], width = width)
  }, character(1))
}

build_and_save_html_report <- function(file, xml_doc, df, subject_meta) {
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
  htmlwidgets::saveWidget(widget, file, selfcontained = TRUE, title = "BLAST results")
}
