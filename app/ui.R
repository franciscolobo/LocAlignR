library(shiny)
library(shinythemes)
library(DT)
library(shinyFiles)

ui <- fluidPage(
  theme = shinytheme("cerulean"),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "style.css"),
    tags$style(HTML("
      .busy, #busy, .busy-indicator, .lds-ellipsis, .three-dots, .dot-typing,
      #loading, #loader, .spinner, .spinner-border,
      div.dataTables_processing, .dataTables_wrapper .dataTables_processing {
        display: none !important; visibility: hidden !important; opacity: 0 !important;
      }
      .panel-heading a { display:block; text-decoration:none; }
      .panel-title { font-weight:600; }
    ")),
    tags$script(HTML("
      $(document).on('shiny:connected', function(){
        $('body').tooltip({selector:'[data-toggle=\"tooltip\"]', container:'body', html:true});
      });
      $(document).on('draw.dt', function(){ $('div.dataTables_processing').hide(); });
    "))
  ),
  
  titlePanel("localBLAST"),
  
  sidebarLayout(
    sidebarPanel(width = 4,
                 
                 div(class = "panel-group", id = "taskAccordion",
                     
                     # ---- Run BLAST (collapsible) ----
                     div(class = "panel panel-default",
                         div(class = "panel-heading",
                             h4(class = "panel-title",
                                a(`data-toggle` = "collapse", `data-parent` = "#taskAccordion",
                                  href = "#collapseRun", "Run BLAST")
                             )
                         ),
                         div(id = "collapseRun", class = "panel-collapse collapse in",
                             div(class = "panel-body",
                                 radioButtons("input_mode", "Sequence input:",
                                              choices = c("Paste" = "paste", "Upload FASTA" = "upload"),
                                              inline = TRUE),
                                 
                                 conditionalPanel(
                                   "input.input_mode == 'paste'",
                                   textAreaInput("query", "Input sequence:", width = "100%", height = "260px")
                                 ),
                                 conditionalPanel(
                                   "input.input_mode == 'upload'",
                                   fileInput("fasta", "FASTA file", multiple = FALSE,
                                             accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt"))
                                 ),
                                 
                                 selectInput("program", "Program:", choices = c("blastp","blastx","blastn","tblastn")),
                                 selectInput("db", "Database:", choices = c("Mlig_core_nt","Mlig_core_aa","nt","nr")),
                                 selectInput("eval", "e-value:", choices = c(1, 0.001, 1e-4, 1e-5, 1e-10)),
                                 
                                 fluidRow(
                                   column(6, actionButton("blast", "run BLAST")),
                                   column(6, downloadButton("download_report", "Download HTML report", class = "btn-primary"))
                                 ),
                                 fluidRow(
                                   column(12, downloadButton("download_xml", "Download BLAST XML"))
                                 )
                             )
                         )
                     ),
                     
                     # ---- Load previous run (collapsible) ----
                     div(class = "panel panel-default",
                         div(class = "panel-heading",
                             h4(class = "panel-title",
                                a(`data-toggle` = "collapse", `data-parent` = "#taskAccordion",
                                  href = "#collapseLoad", "Load saved BLAST XML")
                             )
                         ),
                         div(id = "collapseLoad", class = "panel-collapse collapse",
                             div(class = "panel-body",
                                 fileInput("blast_xml", "Load BLAST XML", accept = c(".xml")),
                                 tags$small(class = "text-muted",
                                            "Loaded results will appear in the Run BLAST results tab.")
                             )
                         )
                     ),
                    
                     # ---- Build database (collapsible) ----
                     div(class = "panel panel-default",
                         div(class = "panel-heading",
                             h4(class = "panel-title",
                                a(`data-toggle` = "collapse", `data-parent` = "#taskAccordion",
                                  href = "#collapseMake", "Build local BLAST database")
                             )
                         ),
                         div(id = "collapseMake", class = "panel-collapse collapse",
                             div(class = "panel-body",
                                 fileInput("make_fasta", "Input FASTA for DB", multiple = FALSE,
                                           accept = c(".fa", ".fasta", ".faa", ".fas", ".fna", ".txt")),
                                 textInput("make_name", "Database name"),
                                 selectInput("make_type", "Type", choices = c("Protein" = "prot", "Nucleotide" = "nucl")),
                                 textInput("make_title", "Title"),
                                 checkboxInput("make_parse", "Parse SeqIDs", value = TRUE),
                                 
                                 # Output directory picker
                                 tags$label("Output directory"),
                                 shinyDirButton("make_outdir_browse", "Browse…", title = "Select output directory"),
                                 tags$small(class = "text-muted", "Selected:"),
                                 verbatimTextOutput("make_outdir_selected", placeholder = TRUE),
                                 textInput("make_outdir", NULL, placeholder = "Or paste a path here", width = "100%"),
                                 
                                 actionButton("make_run", "makeblastdb")
                             )
                         )
                     )
                 )
    ),
    
    mainPanel(width = 8,
              tabsetPanel(id = "main_tabs",
                          tabPanel("Run BLAST results",
                                   h4("Results"),
                                   DTOutput("blastResults"),
                                   hr(),
                                   p("Alignment:", tableOutput("clicked")),
                                   verbatimTextOutput("alignment")
                          ),
                          tabPanel("Build DB log",
                                   h4("DB build log"),
                                   verbatimTextOutput("make_log")
                          )
              )
    )
  )
)