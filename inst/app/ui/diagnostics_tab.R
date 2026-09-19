# inst/app/ui/diagnostics_tab.R

diagnostics_tab <- tabPanel(
  "Diagnostics",

  h4("External tools"),
  tags$ul(
    tags$li(tags$b("BLAST:"), verbatimTextOutput("diag_blast", placeholder = TRUE)),
    tags$li(tags$b("makeblastdb:"), verbatimTextOutput("diag_makeblastdb", placeholder = TRUE)),
    tags$li(tags$b("DIAMOND:"), verbatimTextOutput("diag_diamond", placeholder = TRUE))
  ),

  hr(),
  h5("Session"),
  verbatimTextOutput("diag_session", placeholder = TRUE),

  hr(),
  h5("R packages"),
  verbatimTextOutput("diag_packages", placeholder = TRUE),

  hr(),
  h5("Conda environment"),
  verbatimTextOutput("diag_conda", placeholder = TRUE),

  hr(),
  h5("Configuration files"),
  verbatimTextOutput("diag_config_paths", placeholder = TRUE),

  hr(),
  h5("Storage"),
  verbatimTextOutput("diag_storage", placeholder = TRUE),

  hr(),
  h5("Database registry health"),
  verbatimTextOutput("diag_db_health", placeholder = TRUE),

  hr(),
  h5("Recent log output"),
  actionButton("diag_refresh_log", "Refresh log"),
  br(),
  br(),
  verbatimTextOutput("diag_log_tail", placeholder = TRUE)
)
