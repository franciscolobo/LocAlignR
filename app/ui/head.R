# app/ui/head.R

localign_head <- function() {
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
  )
}
