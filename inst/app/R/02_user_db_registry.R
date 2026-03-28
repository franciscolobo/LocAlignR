# inst/app/R/02_user_db_registry.R

user_db_file <- file.path(
  tools::R_user_dir("LocAlignR", which = "config"),
  "user_dbs.yml"
)

ensure_user_db_dir <- function() {
  dir.create(dirname(user_db_file), recursive = TRUE, showWarnings = FALSE)
}

infer_type <- function(name, path) {
  x <- tolower(paste(name, path))
  if (grepl("(nt|dna|nucl)", x)) "nucl" else "prot"
}

# ---- Seed registry (from config.yml) ----

build_seed_registry <- function(cfg) {
  nms <- names(cfg$databases)
  paths <- unname(unlist(cfg$databases))
  
  data.frame(
    name = nms,
    path = normalizePath(paths, winslash = "/", mustWork = FALSE),
    type = mapply(infer_type, nms, paths, USE.NAMES = FALSE),
    backend = "blast",
    stringsAsFactors = FALSE
  )
}

# ---- Load user registry (with backward compatibility) ----

load_user_dbs <- function(path = user_db_file) {
  empty_df <- data.frame(
    name = character(),
    path = character(),
    type = character(),
    backend = character(),
    stringsAsFactors = FALSE
  )
  
  if (!file.exists(path)) return(empty_df)
  
  y <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (is.null(y) || !length(y)) return(empty_df)
  
  nm <- names(y)
  
  df <- lapply(seq_along(y), function(i) {
    entry <- y[[i]]
    
    path_val <- as.character(entry$path %||% "")
    type_val <- as.character(entry$type %||% infer_type(nm[i], path_val))
    
    backend_val <- entry$backend %||% NA_character_
    
    if (is.na(backend_val) || !nzchar(backend_val)) {
      # Infer backend for old files
      if (grepl("\\.dmnd$", path_val, ignore.case = TRUE)) {
        backend_val <- "diamond"
      } else {
        backend_val <- "blast"
      }
    }
    
    data.frame(
      name = nm[i],
      path = path_val,
      type = type_val,
      backend = tolower(backend_val),
      stringsAsFactors = FALSE
    )
  })
  
  do.call(rbind, df)
}

# ---- Save user registry ----

save_user_dbs <- function(df, path = user_db_file) {
  ensure_user_db_dir()
  
  lst <- setNames(
    lapply(seq_len(nrow(df)), function(i) {
      list(
        path = df$path[i],
        type = df$type[i],
        backend = df$backend[i]
      )
    }),
    df$name
  )
  
  tmp <- paste0(path, ".tmp")
  yaml::write_yaml(lst, tmp)
  file.rename(tmp, path)
}

# ---- Merge seed + user ----

merge_seed_and_user_registry <- function(seed, user) {
  if (!nrow(user)) return(seed)
  
  # User overrides seed if same name
  merged <- seed[!(seed$name %in% user$name), , drop = FALSE]
  merged <- rbind(merged, user)
  
  merged
}

# ---- Allowed DBs per program + aligner ----

allowed_db_choices_for_program <- function(reg, program, aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")
  
  if (identical(aligner, "DIAMOND")) {
    return(reg$name[reg$backend == "diamond" & reg$type == "prot"])
  }
  
  if (program %in% c("blastn", "tblastn")) {
    c(reg$name[reg$backend == "blast" & reg$type == "nucl"], "nt")
  } else {
    c(reg$name[reg$backend == "blast" & reg$type == "prot"], "nr")
  }
}

# ---- Resolve DB selection ----

resolve_db_selection <- function(db_input, registry, program, aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")
  
  # BLAST remote DBs
  if (identical(aligner, "BLAST") && db_input %in% c("nr", "nt")) {
    db_type <- if (db_input == "nt") "nucl" else "prot"
    return(list(db_path = db_input, db_type = db_type, remote = TRUE, backend = "blast"))
  }
  
  row <- registry[match(db_input, registry$name), , drop = FALSE]
  
  shiny::validate(
    shiny::need(nrow(row) == 1 && nzchar(row$path), paste("Unknown DB:", db_input))
  )
  
  db <- row$path
  db_type <- row$type
  backend <- tolower(row$backend %||% "blast")
  
  shiny::validate(
    shiny::need(
      !(identical(aligner, "DIAMOND") && backend != "diamond"),
      "Selected database is not registered for DIAMOND."
    ),
    shiny::need(
      !(identical(aligner, "BLAST") && backend != "blast"),
      "Selected database is not registered for BLAST."
    ),
    shiny::need(
      !(program %in% c("blastn", "tblastn") && db_type != "nucl"),
      "Program needs a nucleotide DB."
    ),
    shiny::need(
      !(program %in% c("blastp", "blastx") && db_type != "prot"),
      "Program needs a protein DB."
    )
  )
  
  list(
    db_path = db,
    db_type = db_type,
    remote = FALSE,
    backend = backend
  )
}