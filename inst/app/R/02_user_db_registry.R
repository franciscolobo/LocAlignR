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

make_db_registry_name <- function(name, backend) {
  name <- trimws(name)
  backend <- tolower(trimws(backend %||% "blast"))
  
  if (grepl("_(blast|diamond)$", name, ignore.case = TRUE)) {
    return(name)
  }
  
  paste0(name, "_", backend)
}

load_or_default_config <- function(cfg_file = "config.yml") {
  cfg_path <- normalizePath(cfg_file, winslash = "/", mustWork = FALSE)
  
  if (file.exists(cfg_path)) {
    cfg <- tryCatch(yaml::read_yaml(cfg_path), error = function(e) NULL)
    if (!is.null(cfg) && !is.null(cfg$databases) && length(cfg$databases)) {
      return(cfg)
    }
  }
  
  list(
    databases = list(
      Mlig_core_nt = "/Users/pereiralobof2/Projects/Erin/WolfBLAST/databases/Mlig_core_nt",
      Mlig_core_aa = "/Users/pereiralobof2/Projects/Erin/WolfBLAST/databases/Mlig_core_aa"
    )
  )
}

log_registry_config <- function(cfg, cfg_file = "config.yml") {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  cfg_exists <- file.exists(cfg_file)
  
  message(sprintf("[REGISTRY] working dir: %s", wd))
  message(sprintf("[REGISTRY] config.yml: %s | exists=%s", cfg_file, cfg_exists))
  
  dbs <- cfg$databases
  if (is.null(dbs) || !length(dbs)) {
    message("[REGISTRY] config.yml has 0 configured databases")
    return(invisible(NULL))
  }
  
  nms <- names(dbs)
  vals <- unname(unlist(dbs))
  
  for (i in seq_along(vals)) {
    message(sprintf("[REGISTRY] config.yml db[%d]: %s -> %s", i, nms[i], vals[i]))
  }
  
  invisible(NULL)
}

log_user_db_file <- function(path, user_df) {
  exists_flag <- file.exists(path)
  message(sprintf("[REGISTRY] user_dbs.yml: %s | exists=%s", path, exists_flag))
  
  if (is.null(user_df) || !nrow(user_df)) {
    message("[REGISTRY] user_dbs.yml has 0 entries")
    return(invisible(NULL))
  }
  
  for (i in seq_len(nrow(user_df))) {
    message(sprintf(
      "[REGISTRY] user_dbs.yml entry: %s -> %s (type=%s, backend=%s)",
      user_df$name[i],
      user_df$path[i],
      user_df$type[i],
      user_df$backend[i]
    ))
  }
  
  invisible(NULL)
}

log_registry_entries <- function(reg) {
  if (is.null(reg) || !nrow(reg)) {
    message("[REGISTRY] merged entries: 0")
    return(invisible(NULL))
  }
  
  message(sprintf("[REGISTRY] merged entries: %d", nrow(reg)))
  
  for (i in seq_len(nrow(reg))) {
    message(sprintf(
      "[REGISTRY] registry: %s -> %s (type=%s, backend=%s)",
      reg$name[i],
      reg$path[i],
      reg$type[i],
      reg$backend[i]
    ))
  }
  
  invisible(NULL)
}

build_seed_registry <- function(cfg) {
  dbs <- cfg$databases
  
  if (is.null(dbs) || !length(dbs)) {
    return(
      data.frame(
        name = character(),
        path = character(),
        type = character(),
        backend = character(),
        title = character(),
        source = character(),
        created = character(),
        version = character(),
        metadata_path = character(),
        has_metadata = logical(),
        stringsAsFactors = FALSE
      )
    )
  }
  
  nms <- names(dbs)
  paths <- unname(unlist(dbs))
  
  data.frame(
    name = nms,
    path = normalizePath(paths, winslash = "/", mustWork = FALSE),
    type = mapply(infer_type, nms, paths, USE.NAMES = FALSE),
    backend = "blast",
    title = nms,
    source = "seed",
    created = "",
    version = "",
    metadata_path = "",
    has_metadata = FALSE,
    stringsAsFactors = FALSE
  )
}

load_user_dbs <- function(path = user_db_file) {
  empty_df <- data.frame(
    name = character(),
    path = character(),
    type = character(),
    backend = character(),
    title = character(),
    source = character(),
    created = character(),
    version = character(),
    metadata_path = character(),
    has_metadata = logical(),
    stringsAsFactors = FALSE
  )
  
  if (!file.exists(path)) return(empty_df)
  
  y <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (is.null(y) || !length(y)) return(empty_df)
  
  nm <- names(y)
  
  rows <- lapply(seq_along(y), function(i) {
    entry <- y[[i]]
    
    path_val <- as.character(entry$path %||% "")
    type_val <- as.character(entry$type %||% infer_type(nm[i], path_val))
    backend_val <- as.character(entry$backend %||% "")
    
    if (!nzchar(backend_val)) {
      backend_val <- if (grepl("\\.dmnd$", path_val, ignore.case = TRUE)) "diamond" else "blast"
    }
    
    data.frame(
      name = nm[i],
      path = path_val,
      type = type_val,
      backend = tolower(backend_val),
      title = as.character(entry$title %||% ""),
      source = as.character(entry$source %||% "user"),
      created = as.character(entry$created %||% ""),
      version = as.character(entry$version %||% ""),
      metadata_path = as.character(entry$metadata_path %||% ""),
      has_metadata = as.logical(entry$has_metadata %||% FALSE),
      stringsAsFactors = FALSE
    )
  })
  
  dplyr::bind_rows(rows)
}

save_user_dbs <- function(df, path = user_db_file) {
  ensure_user_db_dir()
  
  if (is.null(df) || !nrow(df)) {
    tmp <- paste0(path, ".tmp")
    yaml::write_yaml(list(), tmp)
    file.rename(tmp, path)
    return(invisible(NULL))
  }
  
  lst <- setNames(
    lapply(seq_len(nrow(df)), function(i) {
      row <- df[i, , drop = FALSE]
      
      x <- as.list(row)
      x <- lapply(x, function(v) {
        if (length(v) == 0 || is.na(v)) NULL else as.character(v)
      })
      
      x[!vapply(x, is.null, logical(1))]
    }),
    df$name
  )
  
  tmp <- paste0(path, ".tmp")
  yaml::write_yaml(lst, tmp)
  file.rename(tmp, path)
  
  invisible(NULL)
}

merge_seed_and_user_registry <- function(seed, user) {
  if (is.null(seed)) seed <- data.frame(stringsAsFactors = FALSE)
  if (is.null(user)) user <- data.frame(stringsAsFactors = FALSE)
  
  all_cols <- union(names(seed), names(user))
  
  add_missing_cols <- function(df, cols) {
    missing <- setdiff(cols, names(df))
    
    for (nm in missing) {
      df[[nm]] <- ""
    }
    
    df[, cols, drop = FALSE]
  }
  
  seed <- add_missing_cols(seed, all_cols)
  user <- add_missing_cols(user, all_cols)
  
  if (!nrow(seed)) return(user)
  if (!nrow(user)) return(seed)
  
  merged <- seed[!(seed$name %in% user$name), , drop = FALSE]
  merged <- rbind(merged, user)
  rownames(merged) <- NULL
  
  merged
}

allowed_db_choices_for_program <- function(reg, program, aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")
  
  if (identical(aligner, "DIAMOND")) {
    return(reg$name[reg$backend == "diamond" & reg$type == "prot"])
  }
  
  if (program %in% c("blastn", "tblastn", "tblastx")) {
    c(reg$name[reg$backend == "blast" & reg$type == "nucl"], "nt")
  } else {
    c(reg$name[reg$backend == "blast" & reg$type == "prot"], "nr")
  }
}

resolve_db_selection <- function(db_input, registry, program, aligner = "BLAST") {
  aligner <- toupper(aligner %||% "BLAST")
  
  if (identical(aligner, "BLAST") && db_input %in% c("nr", "nt")) {
    db_type <- if (identical(db_input, "nt")) "nucl" else "prot"
    return(list(
      db_path = db_input,
      db_type = db_type,
      remote = TRUE,
      backend = "blast"
    ))
  }
  
  row <- registry[match(db_input, registry$name), , drop = FALSE]
  
  shiny::validate(
    shiny::need(nrow(row) == 1 && nzchar(row$path), paste("Unknown DB:", db_input))
  )
  
  db <- row$path[1]
  db_type <- row$type[1]
  backend <- tolower(row$backend[1] %||% "blast")
  
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
      !(program %in% c("blastn", "tblastn", "tblastx") && db_type != "nucl"),
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