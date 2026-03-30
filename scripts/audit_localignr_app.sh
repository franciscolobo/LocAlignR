#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
APP="${ROOT%/}/inst/app"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$APP" ]] || fail "App directory not found: $APP"

SERVER="$APP/server.R"
REG="$APP/R/02_user_db_registry.R"
BLAST="$APP/R/04_blast_xml.R"
MAKE="$APP/R/05_makeblastdb.R"
DISPATCH="$APP/R/07_aligner_dispatch.R"
BUILD_UI="$APP/ui/panel_build_db.R"
RUN_UI="$APP/ui/panel_run_aligner.R"
LOAD_UI="$APP/ui/panel_load_xml.R"
MAIN_UI="$APP/ui.R"

for f in "$SERVER" "$REG" "$BLAST" "$MAKE" "$DISPATCH" "$BUILD_UI" "$RUN_UI" "$LOAD_UI" "$MAIN_UI"; do
  [[ -f "$f" ]] || fail "Missing file: $f"
done

say "== LocAlignR app consistency audit =="
say "App root: $APP"
say

check_def_or_alias() {
  local file="$1"
  local fn="$2"

  if grep -Eq "^[[:space:]]*${fn}[[:space:]]*<-[[:space:]]*function[[:space:]]*\\(" "$file"; then
    say "OK   def   $fn"
  elif grep -Eq "^[[:space:]]*${fn}[[:space:]]*<-[[:space:]]*[A-Za-z0-9_.]+[[:space:]]*$" "$file"; then
    say "OK   alias $fn"
  else
    say "MISS def   $fn   ($file)"
  fi
}

check_ref_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"

  if grep -Fq "$text" "$file"; then
    say "OK   ref   $label"
  else
    say "MISS ref   $label   ($file)"
  fi
}

count_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  local n
  n="$(grep -Fc "$text" "$file" || true)"
  say "COUNT      $label = $n"
}

check_regex() {
  local file="$1"
  local pat="$2"
  local label="$3"

  if grep -Eq "$pat" "$file"; then
    say "OK   ref   $label"
  else
    say "MISS ref   $label   ($file)"
  fi
}

say "-- Registry helpers --"
for fn in \
  load_or_default_config \
  log_registry_config \
  log_user_db_file \
  log_registry_entries \
  build_seed_registry \
  load_user_dbs \
  save_user_dbs \
  merge_seed_and_user_registry \
  allowed_db_choices_for_program \
  resolve_db_selection
do
  check_def_or_alias "$REG" "$fn"
done
say

say "-- Alignment / parser helpers --"
for fn in \
  validate_alignment_inputs \
  validate_blast_inputs \
  make_query_signature \
  materialize_query_fasta \
  run_blast_as_xml \
  parse_blast_xml_to_df \
  parse_alignment_xml_to_df \
  render_blast_results_dt \
  render_alignment_results_dt \
  render_clicked_summary_table \
  render_alignment_for_row \
  build_and_save_html_report \
  build_and_save_alignment_html_report
do
  check_def_or_alias "$BLAST" "$fn"
done
say

say "-- Dispatcher helpers --"
for fn in \
  aligner_program_choices \
  run_aligner_as_xml \
  parse_aligner_xml_to_df
do
  check_def_or_alias "$DISPATCH" "$fn"
done
say

say "-- DB builder helpers --"
check_def_or_alias "$MAKE" "run_makeblastdb_and_register"
check_ref_fixed "$MAKE" 'make_backend' 'input$make_backend used in builder'
check_ref_fixed "$MAKE" '.dmnd' 'builder handles DIAMOND .dmnd output'
check_ref_fixed "$MAKE" 'backend' 'builder writes backend field'
say

say "-- Server references --"
check_ref_fixed "$SERVER" 'source("R/02_user_db_registry.R")' 'sources registry helpers'
check_ref_fixed "$SERVER" 'source("R/04_blast_xml.R")' 'sources blast/xml helpers'
check_ref_fixed "$SERVER" 'source("R/05_makeblastdb.R")' 'sources db builder'
check_ref_fixed "$SERVER" 'source("R/07_aligner_dispatch.R")' 'sources dispatcher'

check_ref_fixed "$SERVER" 'input$alignmentResults_rows_selected' 'row-click input uses alignmentResults'
check_ref_fixed "$SERVER" 'input$blast' 'run button id still blast'
check_ref_fixed "$SERVER" 'input$blast_xml' 'load xml input still blast_xml'
check_ref_fixed "$SERVER" 'resolve_db_selection(' 'server uses resolve_db_selection'
check_ref_fixed "$SERVER" 'aligner_program_choices(' 'server uses aligner_program_choices'

count_fixed "$SERVER" 'observeEvent(list(input$program, input$aligner)' 'DB-choice observer occurrences'
count_fixed "$SERVER" 'shinyDirChoose(' 'directory chooser blocks'
say

say "-- UI ids expected by server --"
for id in \
  make_fasta \
  make_name \
  make_type \
  make_backend \
  make_title \
  make_parse \
  make_outdir \
  make_outdir_browse \
  make_run
do
  check_ref_fixed "$BUILD_UI" "\"$id\"" "panel_build_db defines $id"
done

check_regex "$RUN_UI" 'panel_run_(blast|alignment)[[:space:]]*<-[[:space:]]*function[[:space:]]*\(' 'run panel function exists'
check_ref_fixed "$MAIN_UI" 'panel_run_blast()' 'ui.R mounts run panel'
check_ref_fixed "$LOAD_UI" 'blast_xml' 'load panel defines xml input'
say

say "-- Backend-aware registry persistence --"
check_ref_fixed "$REG" 'backend' 'registry file supports backend field'
check_ref_fixed "$REG" '.dmnd' 'registry infers or handles DIAMOND paths'
say

say "-- Known red flags --"
db_obs_n="$(grep -Fc 'observeEvent(list(input$program, input$aligner)' "$SERVER" || true)"
if [[ "$db_obs_n" -gt 1 ]]; then
  say "WARN       duplicate DB-choice observers found in server.R"
fi

dir_pick_n="$(grep -Fc 'shinyDirChoose(' "$SERVER" || true)"
if [[ "$dir_pick_n" -gt 1 ]]; then
  say "WARN       duplicate shinyDirChoose blocks found in server.R"
fi

if grep -Fq 'program  = prog' "$SERVER" || grep -Fq 'program = prog' "$SERVER"; then
  say "INFO       server contains program = prog references; ensure they are only inside the run event"
fi

if grep -Fq 'grepl("\\.dmnd$", reg$path' "$SERVER"; then
  say "WARN       server still contains path-suffix DIAMOND filtering instead of registry-based filtering"
fi

say
say "Audit complete."
