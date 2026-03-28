# app/ui/main_tabs.R

source("ui/diagnostics_tab.R", local = FALSE)

main_tabs <- function() {
  tabsetPanel(
    id = "main_tabs",

    tabPanel(
      "Alignment results",
      h4("Results"),
      DTOutput("alignmentResults"),
      hr(),
      p("Alignment:", tableOutput("clicked")),
      verbatimTextOutput("alignment")
    ),

    tabPanel(
      "Build DB log",
      h4("DB build log"),
      verbatimTextOutput("make_log")
    ),
    diagnostics_tab
  )
}
