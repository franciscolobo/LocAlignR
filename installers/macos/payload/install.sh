#!/bin/zsh
set -euo pipefail

# ----------------------------
# LocAlign macOS installer
# ----------------------------

APP_NAME="LocAlign"
USER_CFG_DIR="$HOME/Library/Application Support/${APP_NAME}/config"
USER_DB_YML="${USER_CFG_DIR}/user_dbs.yml"

# Your conda channels (adjust once you publish)
# Keep this order: conda-forge first, then bioconda, then your channel, with strict priority.
CF="conda-forge"
BC="bioconda"
MYCHAN="franciscolobo"   # e.g. "localignr" or your org channel

# Package name in conda
PKG="r-localignr"

# Conda environment name
ENV_NAME="localignr"

# Miniforge bootstrap (when conda is missing)
MINIFORGE_VERSION="25.3.1-0"        # choose a version and keep it pinned
MINIFORGE_PREFIX="$HOME/miniforge3" # install location

# Fill these after you decide the exact installer build:
MINIFORGE_SHA256_ARM64="d9eabd1868030589a1d74017b8723b01cf81b5fec1b9da8021b6fa44be7bbeae"
MINIFORGE_SHA256_X86_64="6c09a3550bb65bdb6d3db6f6c2b890b987b57189f3b71c67a5af49943d2522e8"

# Manifest path
MANIFEST="$(cd "$(dirname "$0")" && pwd)/db_manifest.json"


# Helpers
say() { print -r -- "$@"; }
die() { say "ERROR: $*"; exit 1; }

ask_yes_no() {
  local prompt="$1"
  local reply
  reply=$(osascript -e "button returned of (display dialog \"$prompt\" buttons {\"Skip\",\"Continue\"} default button \"Continue\")" 2>/dev/null || true)
  [[ "$reply" == "Continue" ]]
}

ask_choice() {
  # args: prompt, choices (comma-separated)
  local prompt="$1"
  local choices_csv="$2"
  osascript -e "choose from list {${choices_csv}} with prompt \"$prompt\" default items {item 1 of {${choices_csv}}}" 2>/dev/null || true
}

ask_folder() {
  osascript -e 'POSIX path of (choose folder with prompt "Choose a folder")' 2>/dev/null || true
}

require_continue() {
  local msg="$1"
  ask_yes_no "$msg" || exit 0
}

dl_file() {
  # args: url, outpath
  local url="$1"
  local out="$2"

  if [[ "$url" == file://* ]]; then
    local src="${url#file://}"
    [[ -f "$src" ]] || die "Local file not found: $src"
    cp -f "$src" "$out"
  else
    curl -fL "$url" -o "$out" || die "Download failed: $url"
  fi
}

verify_sha256() {
  # args: filepath, expected_sha256
  local fp="$1"
  local exp="$2"
  [[ -n "$exp" ]] || die "Missing expected sha256 for $fp"
  local got
  got="$(shasum -a 256 "$fp" | awk '{print $1}')"
  [[ "$got" == "$exp" ]] || die "SHA256 mismatch for $fp"
}

manifest_list_tsv() {
  "$CONDA_BIN" run -n "$ENV_NAME" Rscript -e '
    mf <- commandArgs(TRUE)[1]
    m <- jsonlite::read_json(mf, simplifyVector = FALSE)
    if (is.null(m$databases) || length(m$databases) == 0) quit(status = 2)
    for (d in m$databases) {
      cat(d$id, d$display_name, sep = "\t")
      cat("\n")
    }
  ' "$MANIFEST"
}

manifest_get_db_json() {
  # args: db_id
  "$CONDA_BIN" run -n "$ENV_NAME" Rscript -e '
    id <- commandArgs(TRUE)[1]
    mf <- commandArgs(TRUE)[2]
    m <- jsonlite::read_json(mf, simplifyVector = FALSE)
    if (is.null(m$databases) || length(m$databases) == 0) quit(status = 2)
    hit <- NULL
    for (d in m$databases) {
      if (!is.null(d$id) && identical(d$id, id)) { hit <- d; break }
    }
    if (is.null(hit)) quit(status = 3)
    cat(jsonlite::toJSON(hit, auto_unbox = TRUE, pretty = FALSE))
  ' "$1" "$MANIFEST"
}

yaml_upsert_db() {
  # args: name, path, type, backend
  local nm="$1"
  local pth="$2"
  local tp="$3"
  local backend="${4:-blast}"

  mkdir -p "$USER_CFG_DIR"

  "$CONDA_BIN" run -n "$ENV_NAME" Rscript -e '
    suppressPackageStartupMessages({library(yaml)})
    yml <- commandArgs(TRUE)[1]
    nm  <- commandArgs(TRUE)[2]
    pth <- commandArgs(TRUE)[3]
    tp  <- commandArgs(TRUE)[4]
    backend <- commandArgs(TRUE)[5]

    x <- list()
    if (file.exists(yml)) {
      x <- tryCatch(read_yaml(yml), error = function(e) list())
      if (is.null(x)) x <- list()
    }

    x[[nm]] <- list(
      path = pth,
      type = tp,
      backend = backend
    )

    tmp <- paste0(yml, ".tmp")
    write_yaml(x, tmp)
    file.rename(tmp, yml)
  ' "$USER_DB_YML" "$nm" "$pth" "$tp" "$backend"
}

download_format_and_register_db() {
  # args: db_id, display_name, db_dir
  local db_id="$1"
  local display_name="$2"
  local db_dir="$3"

  say ""
  say "Processing: $display_name"

  local db_json
  db_json="$(manifest_get_db_json "$db_id")" || die "Failed to read manifest entry: $db_id"

  local file_tsv
  file_tsv="$("$CONDA_BIN" run -n "$ENV_NAME" Rscript -e '
    d <- jsonlite::fromJSON(commandArgs(TRUE)[1])
    f <- d$files
    cat(paste(f$filename, f$url, f$sha256, sep = "\t"), sep = "\n")
  ' "$db_json")"
  [[ -n "$file_tsv" ]] || die "No files found in manifest for: $db_id"

  local molecule
  molecule="$("$CONDA_BIN" run -n "$ENV_NAME" Rscript -e '
    d <- jsonlite::fromJSON(commandArgs(TRUE)[1])
    cat(d$molecule)
  ' "$db_json")"
  [[ -n "$molecule" ]] || die "Missing molecule type in manifest for: $db_id"

  local db_subdir="${db_dir%/}/${db_id}"
  mkdir -p "$db_subdir"

  while IFS=$'\t' read -r fn url sha; do
    [[ -n "$fn" && -n "$url" && -n "$sha" ]] || die "Malformed file entry for $db_id"
    local out="${db_subdir}/${fn}"
    say "  Fetching: $fn"
    dl_file "$url" "$out"
    verify_sha256 "$out" "$sha"
  done <<< "$file_tsv"

  local gzip_file
  gzip_file="$(printf '%s\n' "$file_tsv" | head -n1 | cut -f1)"
  local in_gz="${db_subdir}/${gzip_file}"
  [[ -f "$in_gz" ]] || die "Expected file missing: $in_gz"

  local fasta_out="${in_gz%.gz}"
  say "  Extracting: $(basename "$in_gz") -> $(basename "$fasta_out")"
  gunzip -c "$in_gz" > "$fasta_out"
  [[ -f "$fasta_out" ]] || die "Failed to create FASTA: $fasta_out"
  say "  Saved FASTA: $fasta_out"

  local db_base="${db_subdir%/}/${db_id}"

  say "  Building BLAST database"
  if [[ "$molecule" == "protein" ]]; then
    "$CONDA_BIN" run -n "$ENV_NAME" makeblastdb \
      -in "$fasta_out" \
      -dbtype prot \
      -out "$db_base" \
      -parse_seqids \
      || die "makeblastdb failed for $db_id"

    yaml_upsert_db "${db_id}_blast" "$db_base" "prot" "blast"
  else
    "$CONDA_BIN" run -n "$ENV_NAME" makeblastdb \
      -in "$fasta_out" \
      -dbtype nucl \
      -out "$db_base" \
      -parse_seqids \
      || die "makeblastdb failed for $db_id"

    yaml_upsert_db "${db_id}_blast" "$db_base" "nucl" "blast"
  fi
  say "  Registered BLAST DB: ${db_id}_blast"

  if [[ "$molecule" == "protein" ]]; then
    say "  Building DIAMOND database"
    "$CONDA_BIN" run -n "$ENV_NAME" diamond makedb \
      --in "$fasta_out" \
      --db "$db_base" \
      || die "diamond makedb failed for $db_id"

    yaml_upsert_db "${db_id}_diamond" "${db_base}.dmnd" "prot" "diamond"
    say "  Registered DIAMOND DB: ${db_id}_diamond"
  fi
}

create_gui_launcher() {
  # Creates ~/Applications/LocAlignR.app
  local target_dir="$HOME/Applications"
  local app="$target_dir/LocAlignR.app"
  local contents="$app/Contents"
  local macos="$contents/MacOS"

  mkdir -p "$macos" || die "Failed to create ~/Applications."

  # If you want the app to be hidden (no Dock icon), set LSUIElement to true below.
  # Most users expect a Dock icon, so default is false (remove LSUIElement).
  cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleName</key>
    <string>LocAlignR</string>
    <key>CFBundleDisplayName</key>
    <string>LocAlignR</string>

    <!-- Use a stable reverse-DNS identifier you control -->
    <key>CFBundleIdentifier</key>
    <string>io.github.franciscolobo.localignr</string>

    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>LocAlignR</string>

    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>

    <!-- Uncomment to hide from Dock/App Switcher -->
    <!-- <key>LSUIElement</key><true/> -->
  </dict>
</plist>
PLIST

  cat > "$macos/LocAlignR" <<'SH'
#!/bin/zsh
set -euo pipefail

APP_NAME="LocAlignR"
ENV_NAME="localignr"

# Prefer explicit installs, then PATH
CANDIDATES=(
  "$HOME/miniforge3/bin/conda"
  "$HOME/miniconda3/bin/conda"
  "$HOME/mambaforge/bin/conda"
  "$(command -v conda || true)"
  "$(command -v mamba || true)"
  "$(command -v micromamba || true)"
)

CONDA_BIN=""
for c in "${CANDIDATES[@]}"; do
  if [[ -n "$c" && -x "$c" ]]; then
    CONDA_BIN="$c"
    break
  fi
done

if [[ -z "$CONDA_BIN" ]]; then
  osascript -e 'display dialog "LocAlignR could not find conda/mamba/micromamba. Re-run the LocAlignR installer." buttons {"OK"} default button 1 with icon stop' >/dev/null 2>&1 || true
  exit 1
fi

# Tool-agnostic env check: try a trivial command inside the env.
if ! "$CONDA_BIN" run -n "$ENV_NAME" R -q -e '1' >/dev/null 2>&1; then
  osascript -e "display dialog \"LocAlignR environment '$ENV_NAME' was not found or is broken. Re-run the LocAlignR installer.\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1 || true
  exit 1
fi

# Sanity check: LocAlignR installed?
if ! "$CONDA_BIN" run -n "$ENV_NAME" R -q -e 'packageVersion("LocAlignR")' >/dev/null 2>&1; then
  osascript -e 'display dialog "LocAlignR is not installed in the conda environment (localignr). Re-run the LocAlignR installer." buttons {"OK"} default button 1 with icon stop' >/dev/null 2>&1 || true
  exit 1
fi

# Tell the user what will happen (helps with the "nothing happened" feeling)
osascript -e 'display dialog "Starting LocAlignR.\n\nA browser window will open in a few seconds.\n\nTo stop LocAlignR, quit this app." buttons {"OK"} default button 1' >/dev/null 2>&1 || true

# Launch the Shiny app
exec "$CONDA_BIN" run -n "$ENV_NAME" R -q -e 'LocAlignR::run_app()'
SH

  chmod +x "$macos/LocAlignR" || die "Failed to make launcher executable."
  touch "$app"
  say "Created GUI launcher: $app"
}


# ----------------------------
# Step 0: intro
# ----------------------------
require_continue "This installer will set up LocAlignR on your Mac.

Steps:
1) Install micromamba/conda if needed
2) Create a conda environment and install LocAlignR
3) Optionally download curated databases, then automatically format and register them

Continue?"

# ----------------------------
# Step 1: conda availability
# ----------------------------
say "== Step 1/4: Checking for conda/micromamba =="

CONDA_BIN=""
if command -v micromamba >/dev/null 2>&1; then
  CONDA_BIN="micromamba"
elif command -v mamba >/dev/null 2>&1; then
  CONDA_BIN="mamba"
elif command -v conda >/dev/null 2>&1; then
  CONDA_BIN="conda"
fi

if [[ -z "$CONDA_BIN" ]]; then
  require_continue "No conda/mamba found.

Install Miniforge (conda-forge based) now? It will be installed to:
${MINIFORGE_PREFIX}"

  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64)   MF_ARCH="arm64";  MF_SHA="$MINIFORGE_SHA256_ARM64" ;;
    x86_64)  MF_ARCH="x86_64"; MF_SHA="$MINIFORGE_SHA256_X86_64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
  esac

  MF_NAME="Miniforge3-${MINIFORGE_VERSION}-MacOSX-${MF_ARCH}.sh"
  MF_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MF_NAME}"
  MF_TMP="$(mktemp -t miniforge.XXXXXX).sh"

  say "Downloading: ${MF_NAME}"
  curl -fL "$MF_URL" -o "$MF_TMP" || die "Failed to download Miniforge."

  if [[ "$MF_SHA" == REPLACE_WITH_SHA256* ]]; then
    die "Miniforge SHA256 is not set. Update MINIFORGE_SHA256_* for ${MF_NAME}."
  fi

  GOT_SHA="$(shasum -a 256 "$MF_TMP" | awk '{print $1}')"
  [[ "$GOT_SHA" == "$MF_SHA" ]] || die "SHA256 mismatch for Miniforge installer."

  chmod +x "$MF_TMP"
  say "Installing Miniforge to: ${MINIFORGE_PREFIX}"
  bash "$MF_TMP" -b -p "$MINIFORGE_PREFIX" || die "Miniforge install failed."
  rm -f "$MF_TMP"

  # Activate conda in this script context
  CONDA_BIN="${MINIFORGE_PREFIX}/bin/conda"
  [[ -x "$CONDA_BIN" ]] || die "conda not found after Miniforge install."

  say "Installed conda: $("$CONDA_BIN" --version)"
else
  say "Found: $CONDA_BIN"
fi

# ----------------------------
# Step 2: create env + install LocAlignR
# ----------------------------
say "== Step 2/4: Installing LocAlignR into a conda environment =="

require_continue "LocAlignR will be installed into conda environment: ${ENV_NAME}

Continue?"

# Strict, reproducible channel behavior: use override-channels.
# Also ensure correct channel ordering for solvability (conda-forge first is typical for R stacks).
"$CONDA_BIN" create -y -n "$ENV_NAME" \
  --override-channels -c "$CF" -c "$BC" -c "$MYCHAN" \
  "$PKG" r-jsonlite r-yaml || die "Conda environment creation/install failed."

say "Installed ${PKG} in environment ${ENV_NAME}"

# ----------------------------
# Step 3: optionally download, format, and register curated databases
# ----------------------------
say "== Step 3/3: Optional curated databases =="

if ask_yes_no "Would you like to download curated databases now? Downloaded databases will be formatted and registered automatically."; then
  [[ -f "$MANIFEST" ]] || die "Missing db_manifest.json: $MANIFEST"

  DB_DIR=$(ask_folder)
  [[ -n "$DB_DIR" ]] || die "No folder selected."
  say "Databases will be downloaded to: $DB_DIR"

  DB_TSV="$(manifest_list_tsv)"
  [[ -n "$DB_TSV" ]] || die "Manifest has no databases."

  DB_NAMES_CSV="$(printf '%s\n' "$DB_TSV" | cut -f2 | sed 's/"/\\"/g' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')"

  CHOSEN="$(osascript 2>/dev/null <<OSA || true
set dbs to {${DB_NAMES_CSV}}
set chosen to choose from list dbs with prompt "Select one or more databases to download" with multiple selections allowed
if chosen is false then
  return ""
end if
set AppleScript's text item delimiters to linefeed
return chosen as text
OSA
)"

  if [[ -z "$CHOSEN" ]]; then
    say "No databases were selected."
  else
    while IFS= read -r disp; do
      disp="$(printf "%s" "$disp" | sed 's/^"//; s/"$//')"
      [[ -n "$disp" ]] || continue

      db_id="$(printf '%s\n' "$DB_TSV" | awk -F'\t' -v d="$disp" '$2==d{print $1; exit}')"
      [[ -n "$db_id" ]] || die "Could not map selection to db id: $disp"

      download_format_and_register_db "$db_id" "$disp" "$DB_DIR"
    done <<< "$CHOSEN"

    say ""
    say "Download, formatting, and registration complete."
  fi
else
  say "Curated database setup was skipped."
fi

# ----------------------------
# Step 5: optionally create launcher app
# ----------------------------
say "== Step 5/5: create LocAlignR launcher app =="

if ask_yes_no "Would you like to create a LocAlignR launcher app in ~/Applications (double-click to run)?"; then
  create_gui_launcher
fi


# ----------------------------
# Final: optionally launch LocAlignR now (GUI)
# ----------------------------
if ask_yes_no "Installation steps completed.

Would you like to launch LocAlignR now?"; then
  say "Launching LocAlignR (GUI)..."

  LAUNCHER_APP="$HOME/Applications/LocAlignR.app"

  # If the launcher does not exist, offer to create it now
  if [[ ! -d "$LAUNCHER_APP" ]]; then
    if ask_yes_no "LocAlignR launcher app was not found in ~/Applications.

Create it now?"; then
      create_gui_launcher
    else
      die "Launcher app not found. Re-run installer and create the launcher, or run LocAlignR from Terminal."
    fi
  fi

  # Launch via Finder (non-blocking, no terminal required)
  open "$LAUNCHER_APP" >/dev/null 2>&1 || die "Failed to open: $LAUNCHER_APP"

else
  say ""
  say "Done. To run LocAlignR later:"
  say "  Double-click: ~/Applications/LocAlignR.app"
  say "  Or (Terminal): $CONDA_BIN run -n ${ENV_NAME} R -q -e 'LocAlignR::run_app()'"
  say ""
fi
