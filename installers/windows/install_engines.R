# Install checksum-verified upstream archives already extracted by Inno Setup.
# Do not overwrite any different existing file (including Conda-owned files).
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
prefix <- normalizePath(Sys.getenv("CONDA_PREFIX"), winslash = "/", mustWork = TRUE)
stopifnot(file.exists(file.path(prefix, "conda-meta", "history")))
bin <- file.path(prefix, "Library", "bin")
dir.create(bin, recursive = TRUE, showWarnings = FALSE)
locate <- function(root, exe) {
  found <- list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  found <- found[tolower(basename(found)) == tolower(exe)]
  if (length(found) != 1L) stop("Expected exactly one ", exe, "; found ", length(found))
  normalizePath(dirname(found), winslash = "/", mustWork = TRUE)
}
blast <- locate(args[1], "blastp.exe")
diamond <- locate(args[2], "diamond.exe")
stopifnot(all(file.exists(file.path(blast, paste0(c("blastn", "blastx", "tblastn", "tblastx", "makeblastdb", "blastdbcmd"), ".exe")))))
files_under <- function(root) {
  list.files(root, recursive = TRUE, full.names = FALSE, all.files = TRUE, no.. = TRUE)
}
blast_files <- files_under(blast)
diamond_files <- list.files(diamond, pattern = "(^diamond\\.exe$|\\.dll$)", ignore.case = TRUE)
# Preserve upstream documentation and licensing files in their original layout.
# No upstream files are bundled in the installer itself.
notices <- file.path(prefix, "upstream-engine-notices")
blast_root <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
diamond_root <- normalizePath(args[2], winslash = "/", mustWork = TRUE)
notice_plan <- function(root, label) {
  rel <- files_under(root)
  rel <- rel[!grepl("\\.(exe|dll|manifest)$", rel, ignore.case = TRUE)]
  data.frame(src = file.path(root, rel), dst = file.path(notices, label, rel))
}
plan <- rbind(data.frame(src = file.path(blast, blast_files), dst = file.path(bin, blast_files)),
              data.frame(src = file.path(diamond, diamond_files), dst = file.path(bin, diamond_files)),
              notice_plan(blast_root, "blast-2.17.0"), notice_plan(diamond_root, "diamond-2.2.8"))
stopifnot(!anyDuplicated(tolower(plan$dst)))
# Validate all existing destinations before making changes. Identical files can
# be reused on retry; different files require a fresh environment.
sha <- function(p) digest::digest(p, algo = "sha256", file = TRUE)
for (i in seq_len(nrow(plan))) {
  if (file.exists(plan$dst[i]) && !identical(sha(plan$src[i]), sha(plan$dst[i])))
    stop("Refusing to overwrite different existing file: ", plan$dst[i])
}
for (i in seq_len(nrow(plan))) {
  dst <- plan$dst[i]
  if (!file.exists(dst)) {
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(plan$src[i], dst, overwrite = FALSE)) stop("Copy failed: ", dst)
  }
  if (!identical(sha(plan$src[i]), sha(dst))) stop("Copy verification failed: ", dst)
}
cat("Installed official BLAST and DIAMOND executables; upstream notices: ", notices, "\n", sep = "")
