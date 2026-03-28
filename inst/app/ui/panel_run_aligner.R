# app/ui/panel_run_aligner.R

panel_run_blast <- function() {
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
            "fasta", "FASTA file", multiple = FALSE,
            accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt")
          )
        ),

        selectInput("aligner", "Aligner:", choices = c("BLAST", "DIAMOND"), selected = "BLAST"),
        selectInput("program", "Program:", choices = c("blastp", "blastx", "blastn", "tblastn")),
        selectInput("db", "Database:", choices = c("Mlig_core_nt", "Mlig_core_aa", "nt", "nr")),
        selectInput("eval", "e-value:", choices = c(1, 0.001, 1e-4, 1e-5, 1e-10)),

        fluidRow(
          column(6, uiOutput("run_action_button")),
          column(6, downloadButton("download_report", "Download HTML report", class = "btn-primary"))
        ),
        fluidRow(
          column(12, downloadButton("download_xml", "Download XML"))
        )
      )
    )
  )
}

