# Only JSON interpretation and YAML registry operations; no downloading or formatting.
args <- commandArgs(TRUE)
stopifnot(length(args) >= 1L)
options(warn = 1)
mode <- args[1]
scalar <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
check <- function(x, msg) if (!isTRUE(x)) stop(msg, call. = FALSE)
clean <- function(x) { check(scalar(x) && !grepl('[\r\n\t]', x), 'Invalid manifest field'); x }
filename <- function(x) { clean(x); check(grepl('^[A-Za-z0-9_][A-Za-z0-9_.-]*$', x) && !grepl('[. ]$',x), 'Unsafe filename'); x }
read_manifest <- function(path) {
  m <- jsonlite::read_json(path, simplifyVector = FALSE)
  check(identical(m$schema_version, '1.0'), 'Unsupported manifest schema')
  check(length(m$databases)>0L, 'Empty manifest')
  ids <- vapply(m$databases, function(d) filename(d$id), '')
  check(!anyDuplicated(tolower(ids)), 'Duplicate database IDs')
  m$databases
}
plan <- function(d) {
  p <- d$post_download; f <- d$files[[1]]; r <- p$register
  check(length(d$files)==1L && identical(f$kind,'archive'), 'Expected one archive')
  check(identical(p$extract$type,'tar.gz'), 'Only tar.gz supported in this installer')
  check(identical(d$molecule,'protein') && identical(r$type,'prot'), 'Expected protein database')
  check(length(p$format_options)==2L, 'Expected two formatting operations')
  tools <- vapply(p$format_options, function(x) x$tool, '')
  check(setequal(tools,c('makeblastdb','diamond')), 'Expected BLAST and DIAMOND')
  inputs <- vapply(p$format_options,function(x) filename(x$input),'')
  check(length(unique(inputs))==1L, 'Different FASTA inputs not supported')
  outputs <- vapply(p$extract$outputs,filename,'')
  meta <- filename(r$metadata_path)
  check(length(outputs)==2L && setequal(outputs,c(inputs[1],meta)), 'Unexpected archive outputs')
  check(grepl('^https://',clean(f$url)), 'HTTPS required')
  check(grepl('^[a-fA-F0-9]{64}$',clean(f$sha256)), 'Invalid SHA256')
  c(filename(d$id), clean(d$display_name), filename(d$version), filename(f$filename),
    f$url, tolower(f$sha256), inputs[1], meta, filename(r$name),
    if(is.null(d$source)) 'curated' else clean(d$source))
}
if (mode == 'plan') {
  stopifnot(length(args)==3L)
  plans <- lapply(read_manifest(args[2]),plan)
  writeLines(unlist(plans,use.names=FALSE),args[3],useBytes=TRUE)
} else if (mode == 'register') {
  stopifnot(length(args)==4L)
  dbs <- read_manifest(args[2]); ids <- vapply(dbs,function(d) d$id,'')
  check(sum(ids==args[3])==1L,'Unknown database')
  p <- plan(dbs[[which(ids==args[3])]])
  directory <- normalizePath(args[4],winslash='/',mustWork=TRUE)
  base <- file.path(directory,p[9]); metadata <- file.path(directory,p[8])
  check(file.exists(metadata) && file.exists(paste0(base,'.dmnd')), 'Missing database or metadata')
  cfg <- tools::R_user_dir('LocAlignR','config'); dir.create(cfg,recursive=TRUE,showWarnings=FALSE)
  registry <- file.path(cfg,'user_dbs.yml')
  x <- if(file.exists(registry)) yaml::read_yaml(registry) else list()
  if(is.null(x)) x <- list()
  check(is.list(x) && (length(x)==0L || (!is.null(names(x)) && all(nzchar(names(x))) && !anyDuplicated(names(x)))), 'Invalid registry; no changes made')
  for (engine in c('blast','diamond')) {
    key <- paste0(p[9],'_',engine)
    x[[key]] <- list(name=key,path=if(engine=='blast') base else paste0(base,'.dmnd'),
      type='prot',backend=engine,title=p[2],source=p[10],version=p[3],metadata_path=metadata,has_metadata=TRUE)
  }
  tmp <- tempfile('user_dbs-',tmpdir=cfg,fileext='.yml')
  yaml::write_yaml(x,tmp)
  check(identical(yaml::read_yaml(tmp),x),'Registry round-trip failed')
  # Keep a backup before replacing the registry. Never discard a parse failure.
  if(file.exists(registry)) {
    backup <- tempfile('user_dbs-backup-',tmpdir=cfg,fileext='.yml')
    check(file.copy(registry,backup),'Could not back up registry')
    if(!file.rename(tmp,registry)) {
      if (!file.copy(tmp,registry,overwrite=TRUE)) {
        file.copy(backup,registry,overwrite=TRUE)
        stop('Registry replacement failed; backup retained at ',backup)
      }
      unlink(tmp)
    }
    message('Registry backup: ',backup)
  } else check(file.rename(tmp,registry),'Could not create registry')
  message('Registered both engines in ',registry)
} else stop('Unknown operation')
