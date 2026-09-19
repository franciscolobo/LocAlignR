#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
APP="${ROOT%/}/inst/app"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$APP" ]] || fail "App directory not found: $APP"

SERVER="$APP/server.R"
REG="$APP/R/02_user_db_registry.R"
RESULTS="$APP/R/04_alignment_results.R"
BLASTRUN="$APP/R/05_blast_run.R"
DIAMOND="$APP/R/06_diamond_run.R"
MAKE="$APP/R/07_makeseqdb.R"
DISPATCH="$APP/R/08_aligner_dispatch.R"
DIAG="$APP/R/90_diagnostics.R"
DBTAB="$APP/R/91_databases.R"
BUILD_UI="$APP/ui/panel_build_db.R"
RUN_UI="$APP/ui/panel_run_aligner.R"
LOAD_UI="$APP/ui/panel_load_xml.R"
TABS_UI="$APP/ui/main_tabs.R"
DIAG_UI="$APP/ui/diagnostics_tab.R"
DBTAB_UI="$APP/ui/databases_tab.R"
MAIN_UI="$APP/ui.R"
LOG_DIR_R="$ROOT/R/log_dir.R"

for f in "$SERVER" "$REG" "$RESULTS" "$BLASTRUN" "$DIAMOND" "$MAKE" "$DISPATCH" \
         "$DIAG" "$DBTAB" "$BUILD_UI" "$RUN_UI" "$LOAD_UI" "$TABS_UI" \
         "$DIAG_UI" "$DBTAB_UI" "$MAIN_UI" "$LOG_DIR_R"; do
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

say "-- Alignment / parser helpers (aligner-agnostic) --"
for fn in \
  validate_alignment_inputs \
  validate_blast_inputs \
  make_query_signature \
  materialize_query_fasta \
  parse_blast_xml_to_df \
  parse_alignment_xml_to_df \
  render_blast_results_dt \
  render_alignment_results_dt \
  render_clicked_summary_table \
  render_alignment_for_row \
  build_and_save_html_report \
  build_and_save_alignment_html_report \
  build_and_save_alignment_xlsx_report
do
  check_def_or_alias "$RESULTS" "$fn"
done
say

say "-- BLAST run helper --"
check_def_or_alias "$BLASTRUN" "run_blast_as_xml"
say

say "-- DIAMOND run helper --"
check_def_or_alias "$DIAMOND" "run_diamond_as_xml"
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
check_def_or_alias "$MAKE" "run_makeseqdb_and_register"
check_ref_fixed "$MAKE" 'make_backend' 'input$make_backend used in builder'
check_ref_fixed "$MAKE" '.dmnd' 'builder handles DIAMOND .dmnd output'
check_ref_fixed "$MAKE" 'backend' 'builder writes backend field'
say

say "-- Log directory helper (package root) --"
check_def_or_alias "$LOG_DIR_R" "localignr_log_dir"
check_def_or_alias "$LOG_DIR_R" "localignr_log_file"
say

say "-- Diagnostics helpers --"
check_def_or_alias "$DIAG" "wire_diagnostics"

for id in \
  diag_blast \
  diag_makeblastdb \
  diag_diamond \
  diag_session \
  diag_packages \
  diag_conda \
  diag_config_paths \
  diag_storage \
  diag_db_health \
  diag_log_tail
do
  check_ref_fixed "$DIAG" "output\$$id" "90_diagnostics.R sets output\$$id"
  check_ref_fixed "$DIAG_UI" "\"$id\"" "diagnostics_tab.R defines $id"
done

check_ref_fixed "$DIAG" 'input$diag_refresh_log' 'diagnostics log tail responds to refresh button'
check_ref_fixed "$DIAG_UI" '"diag_refresh_log"' 'diagnostics_tab.R defines refresh button'
check_ref_fixed "$SERVER" 'wire_diagnostics(' 'server calls wire_diagnostics'
count_fixed "$SERVER" 'wire_diagnostics(' 'wire_diagnostics call occurrences'
say

say "-- Databases tab helpers --"
check_def_or_alias "$DBTAB" "wire_databases"
check_ref_fixed "$DBTAB" 'output$databasesTable' '91_databases.R sets output$databasesTable'
check_ref_fixed "$DBTAB" 'input$db_remove_selected' '91_databases.R responds to remove button'
check_ref_fixed "$DBTAB" 'output$db_remove_status' '91_databases.R sets output$db_remove_status'
check_ref_fixed "$DBTAB_UI" '"databasesTable"' 'databases_tab.R defines databasesTable output'
check_ref_fixed "$DBTAB_UI" '"db_remove_selected"' 'databases_tab.R defines remove button'
check_ref_fixed "$DBTAB_UI" '"db_remove_status"' 'databases_tab.R defines status output'
check_ref_fixed "$SERVER" 'wire_databases(' 'server calls wire_databases'
count_fixed "$SERVER" 'wire_databases(' 'wire_databases call occurrences'
check_ref_fixed "$TABS_UI" 'databases_tab' 'main_tabs.R mounts databases_tab'
say

say "-- Server references --"
check_ref_fixed "$SERVER" 'source("R/02_user_db_registry.R")' 'sources registry helpers'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$RESULTS")\")" 'sources alignment results helpers'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$BLASTRUN")\")" 'sources BLAST run helper'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$DIAMOND")\")" 'sources DIAMOND run helper'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$MAKE")\")" 'sources db builder'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$DISPATCH")\")" 'sources dispatcher'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$DIAG")\"" 'sources diagnostics helpers'
check_ref_fixed "$SERVER" "source(\"R/$(basename "$DBTAB")\"" 'sources databases tab helpers'

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

check_regex "$RUN_UI" 'panel_run_(blast|alignment|aligner)[[:space:]]*<-[[:space:]]*function[[:space:]]*\(' 'run panel function exists'
check_ref_fixed "$MAIN_UI" 'panel_run_aligner()' 'ui.R mounts run panel'
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

wire_diag_n="$(grep -Fc 'wire_diagnostics(' "$SERVER" || true)"
if [[ "$wire_diag_n" -eq 0 ]]; then
  say "WARN       wire_diagnostics() is defined but never called in server.R"
elif [[ "$wire_diag_n" -gt 1 ]]; then
  say "WARN       wire_diagnostics() is called more than once in server.R"
fi

wire_db_n="$(grep -Fc 'wire_databases(' "$SERVER" || true)"
if [[ "$wire_db_n" -eq 0 ]]; then
  say "WARN       wire_databases() is defined but never called in server.R"
elif [[ "$wire_db_n" -gt 1 ]]; then
  say "WARN       wire_databases() is called more than once in server.R"
fi

reg_line="$(grep -n 'db_registry <- reactiveVal' "$SERVER" | head -1 | cut -d: -f1 || true)"
alw_line="$(grep -n 'allowed_db_choices <- function' "$SERVER" | head -1 | cut -d: -f1 || true)"
diag_call_line="$(grep -n 'wire_diagnostics(' "$SERVER" | head -1 | cut -d: -f1 || true)"
db_call_line="$(grep -n 'wire_databases(' "$SERVER" | head -1 | cut -d: -f1 || true)"

if [[ -n "$reg_line" && -n "$diag_call_line" && "$diag_call_line" -lt "$reg_line" ]]; then
  say "WARN       wire_diagnostics() is called before db_registry is defined (line $diag_call_line < $reg_line)"
fi

if [[ -n "$alw_line" && -n "$db_call_line" && "$db_call_line" -lt "$alw_line" ]]; then
  say "WARN       wire_databases() is called before allowed_db_choices is defined (line $db_call_line < $alw_line)"
fi

say
say "Audit complete."
