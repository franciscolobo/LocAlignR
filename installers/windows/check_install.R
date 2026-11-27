suppressPackageStartupMessages(library(LocAlignR))
expected <- commandArgs(trailingOnly=TRUE)
stopifnot(length(expected)==1L, as.character(packageVersion('LocAlignR')) == expected)
cat('LocAlignR R version:', as.character(packageVersion('LocAlignR')), '\n')
prefix <- normalizePath(Sys.getenv('CONDA_PREFIX'), winslash='/', mustWork=TRUE)
for (tool in c('blastn','blastp','blastx','tblastn','tblastx','makeblastdb','blastdbcmd','diamond')) {
  p <- Sys.which(tool)
  stopifnot(nzchar(p),startsWith(tolower(normalizePath(p,winslash='/',mustWork=TRUE)),paste0(tolower(prefix),'/')))
  result <- processx::run(p,if(tool=='diamond') 'version' else '-version')
  cat(result$stdout,'\n')
}
stopifnot(requireNamespace('jsonlite',quietly=TRUE),requireNamespace('yaml',quietly=TRUE))
