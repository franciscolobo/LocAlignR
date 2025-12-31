# inst/app/ui/diagnostics_tab.R

diagnostics_tab <- tabPanel(
  "Diagnostics",
  h4("Environment diagnostics"),
  tags$ul(
    tags$li(tags$b("BLAST:"), verbatimTextOutput("diag_blast", placeholder = TRUE)),
    tags$li(tags$b("makeblastdb:"), verbatimTextOutput("diag_makeblastdb", placeholder = TRUE)),
    tags$li(tags$b("DIAMOND:"), verbatimTextOutput("diag_diamond", placeholder = TRUE))
  ),
  hr(),
  h5("Session"),
  verbatimTextOutput("diag_session", placeholder = TRUE)
)

