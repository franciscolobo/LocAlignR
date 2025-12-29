library(shiny)
library(shinybusy)
library(XML)
library(plyr)
library(dplyr)
library(DT)
library(yaml)
library(processx)
library(digest)
library(htmltools)
library(htmlwidgets)
library(shinyFiles)

`%||%` <- function(a, b) if (!is.null(a)) a else b
logf <- function(...) message(sprintf(...))

# ---------- Metadata load ----------
subject_meta <- local({
  f_tsv <- "metadata/subject_meta.tsv"
  f_csv <- "metadata/subject_meta.csv"
  path <- if (file.exists(f_tsv)) f_tsv else if (file.exists(f_csv)) f_csv else NA_character_
  if (is.na(path)) {
    logf("[META] No metadata file found")
    out <- data.frame(id = character(), stringsAsFactors = FALSE, check.names = FALSE)
    attr(out, "meta_path") <- NA_character_
    return(out)
  }
  logf("[META] Reading: %s", normalizePath(path, winslash = "/"))
  df <- if (grepl("\\.tsv$", path, ignore.case = TRUE)) {
    read.delim(path, sep = "\t", header = TRUE, quote = "", comment.char = "",
               check.names = FALSE, stringsAsFactors = FALSE)
  } else {
    read.csv(path, header = TRUE, quote = "", comment.char = "",
             check.names = FALSE, stringsAsFactors = FALSE)
  }
  n0 <- names(df); idx <- which(tolower(n0) == "id")[1]
  if (!length(idx)) { logf("[META] ERROR: No 'id' column"); df$id <- character(nrow(df)) }
  else if (n0[idx] != "id") names(df)[idx] <- "id"
  df <- dplyr::mutate(df, dplyr::across(dplyr::everything(), as.character))
  attr(df, "meta_path") <- normalizePath(path, winslash = "/")
  logf("[META] Rows: %d | Cols: %d", nrow(df), ncol(df))
  df
})

# ---------- Helper: persistent DB registry ----------
user_db_file <- local({
  d <- file.path(getwd(), "config")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.path(d, "user_dbs.yml")
})

infer_type <- function(nm, path) {
  if (grepl("_nt$", nm, ignore.case = TRUE) || grepl("nucl", path, ignore.case = TRUE)) "nucl"
  else if (grepl("_aa$", nm, ignore.case = TRUE) || grepl("prot|protein|aa", path, ignore.case = TRUE)) "prot"
  else NA_character_
}

load_user_dbs <- function(path = user_db_file) {
  if (!file.exists(path)) {
    data.frame(name = character(), path = character(), type = character(), stringsAsFactors = FALSE)
  } else {
    y <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
    if (is.null(y) || !length(y)) {
      data.frame(name = character(), path = character(), type = character(), stringsAsFactors = FALSE)
    } else {
      nm <- names(y)
      p  <- vapply(y, function(e) as.character(e$path %||% ""), character(1))
      tp <- vapply(y, function(e) as.character(e$type %||% NA_character_), character(1))
      data.frame(name = nm, path = p, type = tp, stringsAsFactors = FALSE)
    }
  }
}

save_user_dbs <- function(df, path = user_db_file) {
  lst <- setNames(lapply(seq_len(nrow(df)), function(i) list(path = df$path[i], type = df$type[i])), df$name)
  tmp <- paste0(path, ".tmp")
  yaml::write_yaml(lst, tmp)
  file.rename(tmp, path)
}

# displays alignment plus coordinates
wrap_alignment_with_coords <- function(qseq, mid, hseq, q_from, q_to, h_from, h_to, width = 40) {
  qv <- strsplit(qseq, "", fixed = TRUE)[[1]]
  mv <- strsplit(mid,   "", fixed = TRUE)[[1]]
  hv <- strsplit(hseq,  "", fixed = TRUE)[[1]]
  n  <- length(qv)
  
  step_val <- function(a, b) ifelse(b >= a, 1L, -1L)
  q_step <- step_val(q_from, q_to)
  h_step <- step_val(h_from, h_to)
  
  coord_vec <- function(chars, start, step) {
    out <- rep(NA_integer_, length(chars)); cur <- as.integer(start)
    for (i in seq_along(chars)) if (chars[i] != "-") { out[i] <- cur; cur <- cur + step }
    out
  }
  qcoord <- coord_vec(qv, q_from, q_step)
  hcoord <- coord_vec(hv, h_from, h_step)
  
  lr <- function(vseg) {
    ii <- which(!is.na(vseg))
    if (!length(ii)) return(c("", ""))
    c(as.character(vseg[min(ii)]), as.character(vseg[max(ii)]))
  }
  
  out <- character()
  for (s in seq(1, n, by = width)) {
    e <- min(s + width - 1, n)
    qs <- paste(qv[s:e], collapse = "")
    ms <- paste(mv[s:e], collapse = "")
    hs <- paste(hv[s:e], collapse = "")
    
    qlr <- lr(qcoord[s:e]); hlr <- lr(hcoord[s:e])
    
    lw <- max(nchar(qlr[1]), nchar(hlr[1]), 1)
    rw <- max(nchar(qlr[2]), nchar(hlr[2]), 1)
    
    out <- c(out,
             sprintf("%-6s %*s  %s  %*s", "Query", lw, qlr[1], qs, rw, qlr[2]),
             sprintf("%-6s %*s  %s  %*s", "",     lw, "",      ms, rw, ""     ),
             sprintf("%-6s %*s  %s  %*s", "Hit",   lw, hlr[1], hs, rw, hlr[2]),
             ""
    )
  }
  paste(out, collapse = "\n")
}

# ---------- ID helpers ----------
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
  vals <- as.list(dfrow[1, , drop = FALSE]); nms <- names(vals)
  vchr <- vapply(vals, function(v) if (length(v)) as.character(v)[1] else "", character(1))
  keep <- nms[!is.na(vchr) & nzchar(vchr)]
  if (!length(keep)) return("No metadata")
  paste(sprintf("<b>%s</b>: %s", htmlEscape(keep), htmlEscape(vchr[keep])), collapse = "<br>")
}

build_text_row <- function(dfrow) {
  if (!nrow(dfrow)) return("No metadata")
  vals <- as.list(dfrow[1, , drop = FALSE]); nms <- names(vals)
  vchr <- vapply(vals, function(v) if (length(v)) as.character(v)[1] else "", character(1))
  keep <- nms[!is.na(vchr) & nzchar(vchr)]
  if (!length(keep)) return("No metadata")
  paste(sprintf("%s: %s", keep, vchr[keep]), collapse = "\n")
}

slice_str <- function(s, width = 40) {
  if (!nzchar(s)) return(character(0))
  starts <- seq(1, nchar(s), by = width)
  ends   <- pmin(starts + width - 1, nchar(s))
  substring(s, starts, ends)
}

wrap_alignment <- function(q, m, h, width = 40) {
  qv <- slice_str(q, width); mv <- slice_str(m, width); hv <- slice_str(h, width)
  n <- max(length(qv), length(mv), length(hv))
  if (n == 0) return("")
  qv <- c(qv, rep("", n - length(qv)))
  mv <- c(mv, rep("", n - length(mv)))
  hv <- c(hv, rep("", n - length(hv)))
  paste(vapply(seq_len(n), function(i) {
    paste0("Query:   ", qv[i], "\n",
           "Midline: ", mv[i], "\n",
           "Hit:     ", hv[i])
  }, character(1)), collapse = "\n\n")
}

align_strings <- function(xml_doc, width = 40) {
  al <- xpathApply(xml_doc, "//Iteration", function(row){
    top <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_qseq")    %>% sapply(xmlValue)
    mid <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_midline") %>% sapply(xmlValue)
    bot <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hseq")    %>% sapply(xmlValue)
    rbind(top, mid, bot)
  })
  if (!length(al)) return(character())
  ax <- do.call("cbind", al)
  vapply(seq_len(ncol(ax)), function(i) {
    wrap_alignment(ax[1, i], ax[2, i], ax[3, i], width = 40)
  }, character(1))
}

# ---------- App server ----------
server <- function(input, output, session) {
  session$onSessionEnded(function() stopApp())
  
  # Base config (seed DBs)
  cfg <- if (file.exists("config.yml")) yaml::read_yaml("config.yml") else list(
    databases = list(
      Mlig_core_nt = "/Users/pereiralobof2/Projects/Erin/localBLAST/databases/Mlig_core_nt",
      Mlig_core_aa = "/Users/pereiralobof2/Projects/Erin/localBLAST/databases/Mlig_core_aa"
    ),
    use_remote_for_standard = TRUE
  )
  cfg_path <- normalizePath("config.yml", winslash = "/", mustWork = FALSE)
  logf("[REGISTRY] working dir: %s", normalizePath(getwd(), winslash = "/"))
  logf("[REGISTRY] config.yml: %s | exists=%s", cfg_path, file.exists(cfg_path))
  if (!is.null(cfg$databases)) {
    nms <- names(cfg$databases); paths <- unname(unlist(cfg$databases))
    for (i in seq_along(nms)) {
      logf("[REGISTRY] config.yml db[%d]: %s -> %s",
           i, nms[i], normalizePath(paths[i], winslash = "/", mustWork = FALSE))
    }
  } else {
    logf("[REGISTRY] config.yml has no 'databases' block")
  }
  
  
  seed <- {
    nms <- names(cfg$databases); paths <- unname(unlist(cfg$databases))
    data.frame(
      name = nms,
      path = normalizePath(paths, winslash = "/", mustWork = FALSE),
      type = mapply(infer_type, nms, paths, USE.NAMES = FALSE),
      stringsAsFactors = FALSE
    )
  }
  
  # Load user DBs from disk and merge (user entries override seed on name collision)
  user_df0 <- load_user_dbs()
  udb_path <- normalizePath(user_db_file, winslash = "/", mustWork = FALSE)
  logf("[REGISTRY] user_dbs.yml: %s | exists=%s", udb_path, file.exists(udb_path))
  if (nrow(user_df0)) {
    invisible(apply(user_df0, 1, function(r)
      logf("[REGISTRY] user_dbs.yml entry: %s -> %s (type=%s)",
           r[["name"]], normalizePath(r[["path"]], winslash = "/", mustWork = FALSE), r[["type"]])
    ))
  } else {
    logf("[REGISTRY] user_dbs.yml has 0 entries")
  }
  
  reg0 <- rbind(
    seed[!(seed$name %in% user_df0$name), ],
    user_df0
  )
  
  logf("[REGISTRY] merged entries: %d", nrow(reg0))
  if (nrow(reg0)) {
    invisible(apply(reg0, 1, function(r)
      logf("[REGISTRY] registry: %s -> %s (type=%s)",
           r[["name"]], normalizePath(r[["path"]], winslash = "/", mustWork = FALSE), r[["type"]])
    ))
  }
  
  db_registry <- reactiveVal(reg0)
  
  # Allowed choices per program
  allowed_db_choices <- function(program) {
    reg <- db_registry()
    if (program %in% c("blastn","tblastn")) {
      c(reg$name[reg$type == "nucl"], "nt")
    } else {
      c(reg$name[reg$type == "prot"], "nr")
    }
  }
  
  # Dynamic DB choices
  observeEvent(input$program, {
    choices <- unique(allowed_db_choices(input$program))
    if (!length(choices)) choices <- if (input$program %in% c("blastn","tblastn")) "nt" else "nr"
    updateSelectInput(session, "db", choices = choices, selected = choices[1])
  }, ignoreInit = FALSE)
  
  # Cache for BLAST XML
  .cache <- new.env(parent = emptyenv())
  
  # Current XML (from a fresh run or a loaded file)
  xml_current <- reactiveVal(NULL)
  
  # Use uploaded FASTA?
  use_upload <- reactive({
    is.list(input$fasta) && !is.null(input$fasta$datapath) &&
      nzchar(input$fasta$datapath) && file.exists(input$fasta$datapath)
  })
  
  # ---------- shinyFiles directory picker wiring ----------
  volumes <- c(
    Home = normalizePath("~", winslash = "/", mustWork = TRUE),
    `Working Dir` = normalizePath(getwd(), winslash = "/", mustWork = TRUE),
    shinyFiles::getVolumes()()
  )
  shinyFiles::shinyDirChoose(input, "make_outdir_browse",
                             roots = volumes, session = session, allowDirCreate = TRUE)
  
  output$make_outdir_selected <- renderText({ input$make_outdir })
  observeEvent(input$make_outdir_browse, {
    sel <- shinyFiles::parseDirPath(volumes, input$make_outdir_browse)
    if (length(sel) == 1 && nzchar(sel)) {
      path <- normalizePath(sel, winslash = "/", mustWork = FALSE)
      updateTextInput(session, "make_outdir", value = path)
    }
  })
  
  # ---- Run BLAST ----
  blastresults <- eventReactive(input$blast, {
    shinybusy::show_modal_spinner(spin = "fading-circle", text = "Running BLAST...")
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    if (identical(input$input_mode, "upload")) {
      validate(need(use_upload(), "Please choose a FASTA file."))
    } else {
      validate(need(nzchar(trimws(input$query)), "Please paste a sequence."))
    }
    
    prog <- match.arg(input$program, c("blastn","tblastn","blastp","blastx"))
    
    db_input <- input$db
    if (db_input %in% c("nr","nt")) {
      db <- db_input
      db_type <- if (db == "nt") "nucl" else "prot"
      remote <- TRUE
    } else {
      reg <- db_registry()
      row <- reg[match(db_input, reg$name), , drop = FALSE]
      validate(need(nrow(row) == 1 && nzchar(row$path), paste("Unknown DB:", db_input)))
      db <- row$path
      db_type <- row$type %||% NA_character_
      remote <- FALSE
    }
    
    validate(
      need(!(prog %in% c("blastn","tblastn") && db_type != "nucl"), "Program needs a nucleotide DB."),
      need(!(prog %in% c("blastp","blastx") && db_type != "prot"), "Program needs a protein DB.")
    )
    
    file_sig <- if (use_upload()) {
      paste0("file:", digest::digest(file = input$fasta$datapath, algo = "md5"))
    } else {
      trimws(input$query)
    }
    key <- digest::digest(list(prog, db_input, input$eval, file_sig))
    if (exists(key, envir = .cache)) {
      xml <- get(key, envir = .cache)
      xml_current(xml)
      return(xml)
    }
    
    if (use_upload()) {
      tmp <- normalizePath(input$fasta$datapath)
    } else {
      tmp <- tempfile(fileext = ".fa"); on.exit(unlink(tmp), add = TRUE)
      q <- trimws(input$query)
      if (startsWith(q, ">")) writeLines(q, tmp) else writeLines(paste0(">Query\n", q), tmp)
    }
    
    args <- c("-query", tmp, "-db", db,
              "-evalue", as.character(input$eval),
              "-outfmt", "5", "-max_hsps", "1", "-max_target_seqs", "10")
    if (remote) {
      args <- c(args, "-remote")
    } else {
      threads <- as.character(max(1L, parallel::detectCores(logical = TRUE) %||% 1L))
      args <- c(args, "-num_threads", threads)
    }
    
    res <- processx::run(prog, args, error_on_status = FALSE, timeout = 600, echo = FALSE)
    validate(need(res$status == 0, paste("BLAST failed:", res$stderr)))
    validate(need(nzchar(res$stdout), "BLAST returned no output."))
    
    xml <- XML::xmlParse(res$stdout, asText = TRUE, useInternalNodes = TRUE)
    assign(key, xml, envir = .cache)
    xml_current(xml)
    xml
  }, ignoreNULL = TRUE)
  
  observeEvent(input$blast, {
    invisible(blastresults())
  })
  
  # ---- Load BLAST XML from file ----
  observeEvent(input$blast_xml, {
    req(is.list(input$blast_xml), nzchar(input$blast_xml$datapath), file.exists(input$blast_xml$datapath))
    xml <- XML::xmlParse(input$blast_xml$datapath, useInternalNodes = TRUE)
    xml_current(xml)
  })
  
  # ---- Parse BLAST XML ----
  parsedresults <- reactive({
    x <- xml_current(); req(!is.null(x))
    results <- xpathApply(x, "//Iteration", function(row){
      query_ID       <- getNodeSet(row, "Iteration_query-def") %>% sapply(xmlValue)
      query_length   <- getNodeSet(row, "Iteration_query-len") %>% sapply(xmlValue)
      hit_ID         <- getNodeSet(row, "Iteration_hits//Hit//Hit_id") %>% sapply(xmlValue)
      bitscore       <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_bit-score") %>% sapply(xmlValue)
      eval           <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_evalue") %>% sapply(xmlValue)
      hsp_q_begin    <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(xmlValue)
      hsp_q_end      <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to") %>% sapply(xmlValue)
      hsp_s_begin    <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(xmlValue)
      hsp_s_end      <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to") %>% sapply(xmlValue)
      eval <- suppressWarnings(as.numeric(eval))
      eval <- signif(eval, digits = 3)
      qlen <- suppressWarnings(as.numeric(query_length))
      hit_length <- suppressWarnings(as.numeric(hsp_q_end) - as.numeric(hsp_q_begin) + 1)
      qfrac <- ifelse(is.finite(hit_length/qlen), round(hit_length/qlen, 2), NA_real_)
      cbind(query_ID, hit_ID, hsp_q_begin, hsp_q_end, hit_length, query_fraction = qfrac, bitscore, eval)
    })
    out <- rbind.fill(lapply(results, function(y) as.data.frame(y, stringsAsFactors = FALSE)))
    logf("[BLAST] Parsed %d rows", nrow(out))
    out
  })
  
  # ---- Results table ----
  output$blastResults <- renderDT({
    df <- parsedresults()
    
    df_join   <- df %>% mutate(.join = canon_id(hit_ID))
    meta_join <- subject_meta %>% mutate(.join = canon_id(id))
    merged <- suppressMessages(left_join(df_join, meta_join, by = ".join"))
    
    right_cols <- setdiff(names(merged), names(df_join))
    meta_cols  <- setdiff(right_cols, c("id", ".join"))
    
    tt <- if (nrow(merged)) {
      vapply(seq_len(nrow(merged)), function(i) {
        if (length(meta_cols)) build_tt_row(merged[i, meta_cols, drop = FALSE]) else "No metadata"
      }, character(1))
    } else character(0)
    
    display <- df
    if (length(tt)) {
      display$hit_ID <- sprintf(
        '<span data-toggle="tooltip" data-html="true" title="%s">%s</span>',
        tt, htmlEscape(df$hit_ID)
      )
    } else {
      display$hit_ID <- htmlEscape(df$hit_ID)
    }
    
    display <- display |>
      mutate(
        hsp_q_begin    = suppressWarnings(as.integer(hsp_q_begin)),
        hsp_q_end      = suppressWarnings(as.integer(hsp_q_end)),
        hit_length     = suppressWarnings(as.integer(hit_length)),
        query_fraction = suppressWarnings(as.numeric(query_fraction)),
        pct_cov        = round(query_fraction * 100, 2),
        bitscore       = suppressWarnings(as.numeric(bitscore)),
        eval           = suppressWarnings(signif(as.numeric(eval), digits = 3))
      )
    
    cols <- c(
      query_ID   = "Query ID",
      hsp_q_begin= "Query begin",
      hsp_q_end  = "Query end",
      hit_ID     = "Hit ID",
      hit_length = "Hit length",
      pct_cov    = "%cov",
      bitscore   = "Bit Score",
      eval       = "e-value"
    )
    display <- display[names(cols)]
    
    datatable(
      display,
      colnames = unname(cols),
      escape = FALSE,
      selection = "single",
      filter = "top",
      options = list(
        pageLength = 10,
        searchHighlight = TRUE,
        drawCallback = JS(
          "$('body').tooltip({selector:'[data-toggle=\"tooltip\"]', container:'body', html:true});"
        )
      )
    ) |>
      formatRound("pct_cov", digits = 2)
  })
  
  # ---- Clicked row summary ----
  output$clicked <- renderTable({
    sel <- input$blastResults_rows_selected; req(length(sel) == 1)
    df    <- parsedresults()
    row   <- df[sel, , drop = FALSE]
    idraw <- as.character(row$hit_ID)
    key   <- canon_id(idraw)
    
    meta_rows <- subject_meta[canon_id(subject_meta$id) == key, , drop = FALSE]
    meta_cols <- setdiff(names(subject_meta), "id")
    tt <- if (nrow(meta_rows)) build_tt_row(meta_rows[, meta_cols, drop = FALSE]) else "No metadata"
    
    id_disp <- sprintf('<span data-toggle="tooltip" data-html="true" title="%s">%s</span>',
                       tt, htmlEscape(idraw))
    
    data.frame(
      Field = c("Query ID","Hit ID","Hit begin","Hit end","Hit length","Query aln fraction","Bit Score","e-value"),
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
  },
  rownames = FALSE, colnames = FALSE,
  sanitize.text.function = function(x) x)
  
  # ---- Alignment text ----
  output$alignment <- renderText({
    sel <- input$blastResults_rows_selected; req(length(sel) == 1)
    x <- xml_current()
    
    # sequences per HSP
    al <- xpathApply(x, "//Iteration", function(row){
      top <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_qseq")    %>% sapply(xmlValue)
      mid <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_midline") %>% sapply(xmlValue)
      bot <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hseq")    %>% sapply(xmlValue)
      rbind(top, mid, bot)
    })
    ax <- do.call("cbind", al)
    
    # coordinates per HSP
    pos <- xpathApply(x, "//Iteration", function(row){
      qf <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-from") %>% sapply(xmlValue)
      qt <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_query-to")   %>% sapply(xmlValue)
      hf <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hit-from")   %>% sapply(xmlValue)
      ht <- getNodeSet(row, "Iteration_hits//Hit//Hsp//Hsp_hit-to")     %>% sapply(xmlValue)
      rbind(qf, qt, hf, ht)
    })
    px <- do.call("cbind", pos)
    
    i <- sel
    wrap_alignment_with_coords(
      qseq   = ax[1, i],
      mid    = ax[2, i],
      hseq   = ax[3, i],
      q_from = as.integer(px[1, i]),
      q_to   = as.integer(px[2, i]),
      h_from = as.integer(px[3, i]),
      h_to   = as.integer(px[4, i]),
      width  = 40
    )
  })
  
  # ---- Report download (uses current XML) ----
  output$download_report <- downloadHandler(
    filename = function() paste0("blast_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html"),
    content = function(file) {
      x   <- isolate(xml_current()); validate(need(!is.null(x), "Load or run BLAST first."))
      df  <- isolate(parsedresults()); validate(need(nrow(df) > 0, "No results to export."))
      
      df_join   <- df %>% mutate(.join = canon_id(hit_ID))
      meta_join <- subject_meta %>% mutate(.join = canon_id(id))
      merged    <- suppressMessages(left_join(df_join, meta_join, by = ".join"))
      right_cols <- setdiff(names(merged), names(df_join))
      meta_cols  <- setdiff(right_cols, c("id", ".join"))
      
      al_vec <- align_strings(x, width = 40)
      if (length(al_vec) != nrow(df)) { length(al_vec) <- nrow(df); al_vec[is.na(al_vec)] <- "" }
      
      tip_vec <- vapply(seq_len(nrow(merged)), function(i){
        meta_txt <- if (length(meta_cols)) build_text_row(merged[i, meta_cols, drop = FALSE]) else "No metadata"
        paste(c("Metadata:", meta_txt, "", "Alignment:", al_vec[i] %||% ""), collapse = "\n")
      }, character(1))
      
      display <- df %>%
        mutate(
          hsp_q_begin    = suppressWarnings(as.integer(hsp_q_begin)),
          hsp_q_end      = suppressWarnings(as.integer(hsp_q_end)),
          hit_length     = suppressWarnings(as.integer(hit_length)),
          query_fraction = suppressWarnings(as.numeric(query_fraction)),
          bitscore       = suppressWarnings(as.numeric(bitscore)),
          eval           = suppressWarnings(as.numeric(eval))
        )
      
      esc_tip <- htmlEscape(tip_vec, attribute = TRUE)
      display$hit_ID <- sprintf('<span class="tt" data-tip="%s">%s</span>', esc_tip, htmlEscape(display$hit_ID))
      
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
      
      widget <- datatable(
        display,
        colnames = unname(cols),
        escape = FALSE,
        selection = "none",
        filter = "top",
        options = list(pageLength = 20, searchHighlight = TRUE)
      ) %>% formatRound("query_fraction", digits = 2)
      
      tooltip_css <- tags$style(HTML("
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
      saveWidget(widget, file, selfcontained = TRUE, title = "BLAST results")
    }
  )
  
  # ---- Download raw BLAST XML ----
  output$download_xml <- downloadHandler(
    filename = function() paste0("blast_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".xml"),
    content  = function(file) {
      doc <- isolate(xml_current()); validate(need(!is.null(doc), "No BLAST XML available"))
      XML::saveXML(doc, file = file)
    }
  )
  
  # -------- makeblastdb integration with persistence --------
  make_log <- reactiveVal("")
  append_make_log <- function(...) make_log(paste0(make_log(), sprintf(...), "\n"))
  output$make_log <- renderText(make_log())
  
  observeEvent(input$make_run, {
    shinybusy::show_modal_spinner(spin = "fading-circle", text = "Building database...")
    on.exit(shinybusy::remove_modal_spinner(), add = TRUE)
    
    validate(need(nzchar(Sys.which("makeblastdb")), "makeblastdb not found on PATH"))
    validate(need(is.list(input$make_fasta) && file.exists(input$make_fasta$datapath), "Choose a FASTA file"))
    validate(need(nzchar(input$make_name), "Provide a database name"))
    validate(need(input$make_type %in% c("prot","nucl"), "Choose a valid type"))
    
    outdir <- if (nzchar(input$make_outdir)) input$make_outdir else getwd()
    dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
    outbase <- normalizePath(file.path(outdir, input$make_name), winslash = "/", mustWork = FALSE)
    
    args <- c("-in", normalizePath(input$make_fasta$datapath, winslash = "/"),
              "-dbtype", input$make_type,
              "-out", outbase)
    if (isTRUE(input$make_parse)) args <- c(args, "-parse_seqids")
    if (nzchar(input$make_title)) args <- c(args, "-title", input$make_title)
    
    append_make_log("[makeblastdb] cmd: makeblastdb %s", paste(shQuote(args), collapse = " "))
    res <- processx::run("makeblastdb", args, error_on_status = FALSE, timeout = 1800, echo = FALSE)
    
    append_make_log("[makeblastdb] exit status: %d", res$status)
    if (nzchar(res$stdout)) append_make_log(res$stdout)
    if (nzchar(res$stderr)) append_make_log(res$stderr)
    validate(need(res$status == 0, "makeblastdb failed"))
    
    # Update in-memory registry
    reg <- db_registry()
    new_row <- data.frame(name = input$make_name, path = outbase, type = input$make_type, stringsAsFactors = FALSE)
    reg <- rbind(reg[reg$name != input$make_name, ], new_row)
    db_registry(reg)
    
    # Persist only user DBs (exclude seed names)
    user_save <- reg[!(reg$name %in% names(cfg$databases)), , drop = FALSE]
    save_user_dbs(user_save)
    
    # Refresh selector
    choices <- unique(allowed_db_choices(input$program))
    if (!(input$make_name %in% choices)) choices <- c(input$make_name, choices)
    updateSelectInput(session, "db", choices = choices, selected = input$make_name)
    
    append_make_log("[makeblastdb] Registered and saved DB '%s' at %s (type=%s)",
                    input$make_name, outbase, input$make_type)
    append_make_log("[makeblastdb] Registry file: %s", user_db_file)
  })
}

server