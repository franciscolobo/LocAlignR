# app/ui/panel_load_xml.R

panel_load_xml <- function() {
  div(
    class = "panel panel-default",
    div(
      class = "panel-heading",
      h4(
        class = "panel-title",
        a(
          `data-toggle` = "collapse",
          `data-parent` = "#taskAccordion",
          href = "#collapseLoad",
          "Load saved alignment XML"
        )
      )
    ),
    div(
      id = "collapseLoad",
      class = "panel-collapse collapse",
      div(
        class = "panel-body",
        fileInput("blast_xml", "Load alignment XML", accept = c(".xml")),
        tags$small(
          class = "text-muted",
          "Loaded results will appear in the Run Alignment results tab."
        )
      )
    )
  )
}
