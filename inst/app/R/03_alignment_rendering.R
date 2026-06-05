# R/03_alignment_rendering.R

slice_str <- function(s, width = 40) {
  if (!nzchar(s)) return(character(0))
  starts <- seq(1, nchar(s), by = width)
  ends   <- pmin(starts + width - 1, nchar(s))
  substring(s, starts, ends)
}

wrap_alignment <- function(q, m, h, width = 40) {
  qv <- slice_str(q, width)
  mv <- slice_str(m, width)
  hv <- slice_str(h, width)

  n <- max(length(qv), length(mv), length(hv))
  if (n == 0) return("")

  qv <- c(qv, rep("", n - length(qv)))
  mv <- c(mv, rep("", n - length(mv)))
  hv <- c(hv, rep("", n - length(hv)))

  paste(
    vapply(seq_len(n), function(i) {
      paste0(
        "Query:   ", qv[i], "\n",
        "Midline: ", mv[i], "\n",
        "Hit:     ", hv[i]
      )
    }, character(1)),
    collapse = "\n\n"
  )
}

# Displays alignment plus coordinates
wrap_alignment_with_coords <- function(qseq, mid, hseq,
                                       q_from, q_to,
                                       h_from, h_to,
                                       width = 40) {
  qseq <- paste(as.character(qseq), collapse = "")
  mid  <- paste(as.character(mid), collapse = "")
  hseq <- paste(as.character(hseq), collapse = "")
  
  if (!nzchar(mid)) {
    mid <- paste(rep(" ", nchar(qseq)), collapse = "")
  }
  
  q_from <- as.integer(q_from)
  q_to   <- as.integer(q_to)
  h_from <- as.integer(h_from)
  h_to   <- as.integer(h_to)
  width  <- as.integer(width)
  
  if (!nzchar(qseq) || !nzchar(hseq)) {
    return("Alignment sequence is missing.")
  }
  
  if (!is.finite(q_from) || !is.finite(q_to) ||
      !is.finite(h_from) || !is.finite(h_to)) {
    return("Alignment coordinates are missing.")
  }
  
  n <- nchar(qseq)
  starts <- seq(1, n, by = width)
  
  q_forward <- q_to >= q_from
  h_forward <- h_to >= h_from
  
  q_pos <- q_from
  h_pos <- h_from
  
  chunks <- lapply(starts, function(start) {
    end <- min(start + width - 1, n)
    
    q_chunk <- substr(qseq, start, end)
    m_chunk <- substr(mid, start, end)
    h_chunk <- substr(hseq, start, end)
    
    q_letters <- nchar(gsub("-", "", q_chunk))
    h_letters <- nchar(gsub("-", "", h_chunk))
    
    q_start <- q_pos
    h_start <- h_pos
    
    if (q_letters > 0) {
      q_end <- if (q_forward) q_pos + q_letters - 1L else q_pos - q_letters + 1L
      q_pos <<- if (q_forward) q_end + 1L else q_end - 1L
    } else {
      q_end <- q_start
    }
    
    if (h_letters > 0) {
      h_end <- if (h_forward) h_pos + h_letters - 1L else h_pos - h_letters + 1L
      h_pos <<- if (h_forward) h_end + 1L else h_end - 1L
    } else {
      h_end <- h_start
    }
    
    paste0(
      sprintf("Query %6d  %s  %6d", q_start, q_chunk, q_end), "\n",
      sprintf("             %s", m_chunk), "\n",
      sprintf("Sbjct %6d  %s  %6d", h_start, h_chunk, h_end)
    )
  })
  
  paste(unlist(chunks), collapse = "\n\n")
}