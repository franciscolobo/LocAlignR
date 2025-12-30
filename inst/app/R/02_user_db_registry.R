# R/02_user_db_registry.R

# Persistent DB registry file location
user_db_file <- local({
  d <- file.path(rappdirs::user_config_dir("LocAlign"), "config")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.path(d, "user_dbs.yml")
})

load_or_default_config <- function(cfg_file) {
  if (file.exists(cfg_file)) {
    yaml::read_yaml(cfg_file)
  } else {
    # Default fallback (kept identical to your current behavior)
    list(
      databases = list(
        Mlig_core_nt = "/Users/pereiralobof2/Projects/Erin/localBLAST/databases/Mlig_core_nt",
        Mlig_core_aa = "/Users/pereiralobof2/Projects/Erin/localBLAST/databases/Mlig_core_aa"
      ),
      use_remote_for_standard = TRUE
    )
  }
}

log_registry_config <- function(cfg, cfg_file) {
  cfg_path <- normalizePath(cfg_file, winslash = "/", mustWork = FALSE)
  logf("[REGISTRY] working dir: %s", normalizePath(getwd(), winslash = "/"))
  logf("[REGISTRY] %s: %s | exists=%s", cfg_file, cfg_path, file.exists(cfg_path))

  if (!is.null(cfg$databases)) {
    nms <- names(cfg$databases)
    paths <- unname(unlist(cfg$databases))
    for (i in seq_along(nms)) {
      logf(
        "[REGISTRY] %s db[%d]: %s -> %s",
        cfg_file, i, nms[i], normalizePath(paths[i], winslash = "/", mustWork = FALSE)
      )
    }
  } else {
    logf("[REGISTRY] %s has no 'databases' block", cfg_file)
  }
}

infer_type <- function(nm, path) {
  if (grepl("_nt$", nm, ignore.case = TRUE) || grepl("nucl", path, ignore.case = TRUE)) "nucl"
  else if (grepl("_aa$", nm, ignore.case = TRUE) || grepl("prot|protein|aa", path, ignore.case = TRUE)) "prot"
  else NA_character_
}

build_seed_registry <- function(cfg) {
  nms <- names(cfg$databases)
  paths <- unname(unlist(cfg$databases))
  data.frame(
    name = nms,
    path = normalizePath(paths, winslash = "/", mustWork = FALSE),
    type = mapply(infer_type, nms, paths, USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
}

load_user_dbs <- function(path = user_db_file) {
  if (!file.exists(path)) {
    data.frame(name = character(), path = character(), type = character(), stringsAsFactors = FALSE)
  } else {
    y <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
    if (is.null(y) || !length(y)) {
      data.frame(name = character(), path = character(), type = character(), stringsAsFactors = FALSE)
    } else {
      nm <- names(y)
      p  <- vapply(y, function(e) as.character(e$path %||% ""), character(1))
      tp <- vapply(y, function(e) as.character(e$type %||% NA_character_), character(1))
      data.frame(name = nm, path = p, type = tp, stringsAsFactors = FALSE)
    }
  }
}

save_user_dbs <- function(df, path = user_db_file) {
  lst <- setNames(
    lapply(seq_len(nrow(df)), function(i) list(path = df$path[i], type = df$type[i])),
    df$name
  )
  tmp <- paste0(path, ".tmp")
  yaml::write_yaml(lst, tmp)
  file.rename(tmp, path)
}

merge_seed_and_user_registry <- function(seed, user_df0) {
  rbind(
    seed[!(seed$name %in% user_df0$name), ],
    user_df0
  )
}

log_user_db_file <- function(path, user_df0) {
  udb_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  logf("[REGISTRY] user_dbs.yml: %s | exists=%s", udb_path, file.exists(udb_path))

  if (nrow(user_df0)) {
    invisible(apply(user_df0, 1, function(r) {
      logf(
        "[REGISTRY] user_dbs.yml entry: %s -> %s (type=%s)",
        r[["name"]],
        normalizePath(r[["path"]], winslash = "/", mustWork = FALSE),
        r[["type"]]
      )
    }))
  } else {
    logf("[REGISTRY] user_dbs.yml has 0 entries")
  }
}

log_registry_entries <- function(reg) {
  logf("[REGISTRY] merged entries: %d", nrow(reg))
  if (nrow(reg)) {
    invisible(apply(reg, 1, function(r) {
      logf(
        "[REGISTRY] registry: %s -> %s (type=%s)",
        r[["name"]],
        normalizePath(r[["path"]], winslash = "/", mustWork = FALSE),
        r[["type"]]
      )
    }))
  }
}

allowed_db_choices_for_program <- function(reg, program) {
  if (program %in% c("blastn", "tblastn")) {
    c(reg$name[reg$type == "nucl"], "nt")
  } else {
    c(reg$name[reg$type == "prot"], "nr")
  }
}

resolve_db_selection <- function(db_input, registry, program) {
  if (db_input %in% c("nr", "nt")) {
    db <- db_input
    db_type <- if (db == "nt") "nucl" else "prot"
    remote <- TRUE
    list(db_path = db, db_type = db_type, remote = remote)
  } else {
    row <- registry[match(db_input, registry$name), , drop = FALSE]
    shiny::validate(shiny::need(nrow(row) == 1 && nzchar(row$path), paste("Unknown DB:", db_input)))

    db <- row$path
    db_type <- row$type %||% NA_character_
    remote <- FALSE

    # Enforce type compatibility with program
    shiny::validate(
      shiny::need(!(program %in% c("blastn", "tblastn") && db_type != "nucl"), "Program needs a nucleotide DB."),
      shiny::need(!(program %in% c("blastp", "blastx") && db_type != "prot"), "Program needs a protein DB.")
    )

    list(db_path = db, db_type = db_type, remote = remote)
  }
}
