# app/ui.R

library(shiny)
library(shinythemes)
library(DT)
library(shinyFiles)

source("ui/head.R")
source("ui/panel_run_blast.R")
source("ui/panel_load_xml.R")
source("ui/panel_build_db.R")
source("ui/main_tabs.R")

ui <- fluidPage(
  theme = shinytheme("cerulean"),
  localign_head(),
  
  titlePanel("localBLAST"),
  
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