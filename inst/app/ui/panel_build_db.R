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
          href = "#collapseBuildDb",
          "Build local database"
        )
      )
    ),
    div(
      id = "collapseBuildDb",
      class = "panel-collapse collapse",
      div(
        class = "panel-body",
        
        textInput("make_name", "Database name"),
        
        textInput(
          "make_title",
          "Database title",
          value = ""
        ),
        
        fileInput(
          "make_fasta",
          "FASTA file",
          multiple = FALSE,
          accept = c(".fa", ".faa", ".fasta", ".fas", ".fna", ".txt")
        ),
        
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
        
        checkboxInput(
          "make_parse",
          "Parse SeqIDs",
          value = TRUE
        ),
        
        textInput(
          "make_outdir",
          "Output directory",
          value = ""
        ),
        
        shinyFilesButton(
          "make_outdir_browse",
          "Browse...",
          "Select output directory",
          multiple = FALSE
        ),
        
        br(),
        textOutput("make_outdir_selected"),
        
        tags$small(
          class = "text-muted",
          "DIAMOND supports protein databases only."
        ),
        
        br(),
        br(),
        
        actionButton("make_run", "Build database", class = "btn-primary"),
        
        br(),
        br(),
        
        tags$label("Build log"),
        verbatimTextOutput("make_log", placeholder = TRUE)
      )
    )
  )
}