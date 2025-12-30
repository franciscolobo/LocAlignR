# app/ui/panel_build_db.R

panel_build_db <- function() {
  div(
    class = "panel panel-default",
    div(
      class = "panel-heading",
      h4(
        class = "panel-title",
        a(
          `data-toggle` = "collapse",
          `data-parent` = "#taskAccordion",
          href = "#collapseMake",
          "Build local BLAST database"
        )
      )
    ),
    div(
      id = "collapseMake",
      class = "panel-collapse collapse",
      div(
        class = "panel-body",

        fileInput(
          "make_fasta", "Input FASTA for DB", multiple = FALSE,
          accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt")
        ),
        textInput("make_name", "Database name"),
        selectInput("make_type", "Type", choices = c("Protein" = "prot", "Nucleotide" = "nucl")),
        textInput("make_title", "Title"),
        checkboxInput("make_parse", "Parse SeqIDs", value = TRUE),

        tags$label("Output directory"),
        shinyDirButton("make_outdir_browse", "Browse…", title = "Select output directory"),
        tags$small(class = "text-muted", "Selected:"),
        verbatimTextOutput("make_outdir_selected", placeholder = TRUE),
        textInput("make_outdir", NULL, placeholder = "Or paste a path here", width = "100%"),

        actionButton("make_run", "makeblastdb")
      )
    )
  )
}
