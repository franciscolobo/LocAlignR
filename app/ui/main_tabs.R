# app/ui/main_tabs.R

main_tabs <- function() {
  tabsetPanel(
    id = "main_tabs",

    tabPanel(
      "Run BLAST results",
      h4("Results"),
      DTOutput("blastResults"),
      hr(),
      p("Alignment:", tableOutput("clicked")),
      verbatimTextOutput("alignment")
    ),

    tabPanel(
      "Build DB log",
      h4("DB build log"),
      verbatimTextOutput("make_log")
    )
  )
}
