# app/ui.R

library(shiny)
library(shinythemes)
library(DT)
library(shinyFiles)

source("ui/head.R", local = FALSE)
source("ui/panel_run_blast.R", local = FALSE)
source("ui/panel_load_xml.R", local = FALSE)
source("ui/panel_build_db.R", local = FALSE)
source("ui/diagnostics_tab.R", local = FALSE)
source("ui/main_tabs.R", local = FALSE)

ui <- fluidPage(
  theme = shinytheme("cerulean"),
  localign_head(),
  
  titlePanel("LocAlign"),
  
  sidebarLayout(
    sidebarPanel(
      width = 4,
      div(
        class = "panel-group",
        id = "taskAccordion",
        panel_run_blast(),
        panel_load_xml(),
        panel_build_db()
      )
    ),
    
    mainPanel(
      width = 8,
      main_tabs()
    )
  )
)
