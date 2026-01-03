#!/usr/bin/env Rscript

# logo.R
# LocAlign hex sticker generation using hexSticker + ggplot2
# LocAlign logo & banner using ggplot2

# ----------------------------
# Functions
# ----------------------------

save_square_logo <- function(plot) {
  out_file <- file.path(OUT_DIR, "localign_square_logo.png")

  p <- plot

  p <- p +
  ggplot2::annotate("text", x = 0.5, y = 0.06, label = "LocAlign", size = 10, fontface = "bold", color = "white")

  ggplot2::ggsave(
    filename = out_file,
    plot = p,
    width = 2,
    height = 2,
    units = "in",
    dpi = 320,
    bg = "#1F3A5F"
  )

  message("Wrote: ", out_file)
  invisible(out_file)
}

save_banner_logo <- function(plot) {
  out_file <- file.path(OUT_DIR, "localign_banner.png")
   
  p <- plot
  p <- p +
  ggplot2::annotate("text", x = 0.05, y = 0.92, label = "LocAlign", hjust = 0, size = 10, fontface = "bold", color = "white")

  ggplot2::ggsave(
    filename = out_file,
    plot = p,
    width = 10,
    height = 2,
    units = "in",
    dpi = 320,
    bg = "#1F3A5F"
  )

  message("Wrote: ", out_file)
  invisible(out_file)
}

plot_alignment_lines <- function() {
  ggplot2::ggplot() +
    ggplot2::geom_segment(ggplot2::aes(x = 0.10, xend = 0.92, y = 0.85, yend = 0.85),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0.20, xend = 0.88, y = 0.72, yend = 0.72),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0.08, xend = 0.76, y = 0.59, yend = 0.59),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0.26, xend = 0.94, y = 0.46, yend = 0.46),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0.14, xend = 0.74, y = 0.33, yend = 0.33),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::geom_segment(ggplot2::aes(x = 0.30, xend = 0.86, y = 0.20, yend = 0.20),
                    linewidth = 2.2, color = "white", lineend = "round") +
    ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    ggplot2::theme_void()
}

make_sticker_alignment_lines <- function(plot) {

  hexSticker::sticker(
    subplot = plot,
    package = "LocAlign",
    p_size = 18,
    p_color = "white",
    p_y = 1.55,
    s_x = 1,
    s_y = 0.85,
    s_width = 1.35,
    s_height = 1.35,
    h_fill = "#1F3A5F",
    h_color = "#1F3A5F",
    url = "github.com/franciscolobo/LocAlign",
    u_color = "white",
    u_size = 4,
    u_y = 0.08,
    filename = file.path(OUT_DIR, "localign_hexagonal_logo.png")
  )
}

# ----------------------------
# Main
# ----------------------------

OUT_DIR <- file.path(getwd(), "docs", "logo")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

library(ggplot2)
library(hexSticker)

message("Output directory: ", OUT_DIR)

#creating aligned lines to feed

p <- plot_alignment_lines()

make_sticker_alignment_lines(plot = p)

save_square_logo(plot = p)

#save_banner_logo(plot = p)

# Provenance
session_file <- file.path(OUT_DIR, "sessionInfo.txt")
writeLines(capture.output(sessionInfo()), con = session_file)
message("Wrote: ", session_file)

message("Done.")
