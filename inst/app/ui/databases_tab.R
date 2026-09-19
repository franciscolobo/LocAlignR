# inst/app/ui/databases_tab.R

databases_tab <- tabPanel(
  "Databases",

  h4("Registered databases"),
  p(
    "Databases available for BLAST/DIAMOND runs. Entries you built or ",
    "registered (source = \"user\") can be removed below. Built-in entries ",
    "from config.yml (source = \"seed\") cannot be removed here."
  ),
  tags$p(
    tags$em(
      "Removing an entry only unregisters it from LocAlignR -- it does not ",
      "delete any files from disk."
    )
  ),

  DT::DTOutput("databasesTable"),

  hr(),

  actionButton("db_remove_selected", "Remove selected database(s)", class = "btn-danger"),
  br(),
  br(),
  verbatimTextOutput("db_remove_status", placeholder = TRUE)
)

