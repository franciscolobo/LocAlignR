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
          "Build local sequence database"
        )
      )
    ),
    div(
      id = "collapseMake",
      class = "panel-collapse collapse",
      div(
        class = "panel-body",
        
        fileInput(
          "make_fasta",
          "Input FASTA for DB",
          multiple = FALSE,
          accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt")
        ),
        
        textInput("make_name", "Database name"),
        
        selectInput(
          "make_type",
          "Type",
          choices = c("Protein" = "prot", "Nucleotide" = "nucl"),
          selected = "prot"
        ),
        
        selectInput(
          "make_backend",
          "Backend",
          choices = c("BLAST" = "blast", "DIAMOND" = "diamond"),
          selected = "blast"
        ),
        
        textInput("make_title", "Title"),
        checkboxInput("make_parse", "Parse SeqIDs", value = TRUE),
        
        textInput(
          "make_outdir",
          "Output directory",
          value = "",
          placeholder = "Leave empty to use the current working directory, or paste a full path"
        ),
        
        tags$small(
          class = "text-muted",
          "DIAMOND supports protein databases only."
        ),
        
        br(),
        br(),
        
        actionButton("make_run", "Build database"),
        
        br(),
        br(),
        
        verbatimTextOutput("make_log", placeholder = TRUE)
      )
    )
  )
}