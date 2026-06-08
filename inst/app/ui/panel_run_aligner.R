# app/ui/panel_run_aligner.R

panel_run_aligner <- function() {
  div(
    class = "panel panel-default",
    div(
      class = "panel-heading",
      h4(
        class = "panel-title",
        a(
          `data-toggle` = "collapse",
          `data-parent` = "#taskAccordion",
          href = "#collapseRun",
          uiOutput("run_panel_title")
        )
      )
    ),
    div(
      id = "collapseRun",
      class = "panel-collapse collapse in",
      div(
        class = "panel-body",
        
        radioButtons(
          "input_mode", "Sequence input:",
          choices = c("Paste" = "paste", "Upload FASTA" = "upload"),
          inline = TRUE
        ),
        
        conditionalPanel(
          "input.input_mode == 'paste'",
          textAreaInput("query", "Input sequence:", width = "100%", height = "260px")
        ),
        
        conditionalPanel(
          "input.input_mode == 'upload'",
          fileInput(
            "fasta",
            "FASTA file",
            multiple = FALSE,
            accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt")
          )
        ),
        
        fluidRow(
          column(
            width = 6,
            selectInput(
              "aligner",
              "Aligner:",
              choices = c("BLAST", "DIAMOND"),
              selected = "BLAST"
            )
          ),
          column(
            width = 6,
            selectInput(
              "program",
              "Program:",
              choices = c("blastp", "blastx", "blastn", "tblastn", "tblastx")
            )
          )
        ),
        
        selectInput(
          "db",
          "Database:",
          choices = c("Mlig_core_nt", "Mlig_core_aa", "nt", "nr")
        ),
        
        textInput(
          "eval",
          "e-value:",
          value = "1e-5",
          placeholder = "e.g. 1e-5, 0.001, 10"
        ),
        
        uiOutput("aligner_preset_control"),
        
        checkboxInput(
          "show_advanced_params",
          "Show advanced parameters",
          value = FALSE
        ),
        
        uiOutput("aligner_param_controls"),
        
        tags$hr(),
        
        fluidRow(
          column(
            width = 12,
            uiOutput("run_action_button")
          )
        ),
        
        br(),
        
        tags$h5("Downloads"),
        
        fluidRow(
          column(
            width = 6,
            downloadButton("download_report", "HTML report")
          ),
          column(
            width = 6,
            downloadButton("download_xml", "XML")
          )
        ),
        
        br(),
        
        fluidRow(
          column(
            width = 6,
            downloadButton("download_strategy", "Search strategy")
          ),
          column(
            width = 6,
            downloadButton("download_job_report", "Job report")
          )
        ),
        
        br(),
        
        tags$h5("Load strategy"),
        
        fileInput(
          "upload_strategy",
          label = NULL,
          accept = c(".json"),
          buttonLabel = "Browse...",
          placeholder = "No strategy selected"
        )
      )
    )
  )
}