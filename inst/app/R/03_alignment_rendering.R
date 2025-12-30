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
wrap_alignment_with_coords <- function(qseq, mid, hseq, q_from, q_to, h_from, h_to, width = 40) {
  qv <- strsplit(qseq, "", fixed = TRUE)[[1]]
  mv <- strsplit(mid,  "", fixed = TRUE)[[1]]
  hv <- strsplit(hseq, "", fixed = TRUE)[[1]]
  n  <- length(qv)

  step_val <- function(a, b) ifelse(b >= a, 1L, -1L)
  q_step <- step_val(q_from, q_to)
  h_step <- step_val(h_from, h_to)

  coord_vec <- function(chars, start, step) {
    out <- rep(NA_integer_, length(chars))
    cur <- as.integer(start)
    for (i in seq_along(chars)) {
      if (chars[i] != "-") {
        out[i] <- cur
        cur <- cur + step
      }
    }
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

    qlr <- lr(qcoord[s:e])
    hlr <- lr(hcoord[s:e])

    lw <- max(nchar(qlr[1]), nchar(hlr[1]), 1)
    rw <- max(nchar(qlr[2]), nchar(hlr[2]), 1)

    out <- c(
      out,
      sprintf("%-6s %*s  %s  %*s", "Query", lw, qlr[1], qs, rw, qlr[2]),
      sprintf("%-6s %*s  %s  %*s", "",     lw, "",      ms, rw, ""     ),
      sprintf("%-6s %*s  %s  %*s", "Hit",  lw, hlr[1], hs, rw, hlr[2]),
      ""
    )
  }

  paste(out, collapse = "\n")
}
