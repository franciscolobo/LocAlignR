# LocAlignR taxonomy: phase 4 (native search filters)

Apply to `feature/taxonomy` after Phase 3. Patch based on the uploaded release-review repository plus the Phase 1–3 patches; not a live branch checkout. Run `git apply --check` before applying.

## Behavior

- Run alignment panel: choose None, Include taxa, or Exclude taxa; enter one or more NCBI TaxIDs separated by commas/spaces. Filters appear for taxonomy-capable local databases. Switching to an incompatible database with an active filter preserves the filter controls and rejects the search until cleared, rather than silently dropping it.
- Resolve merged IDs and reject invalid/deleted IDs using the snapshot registered for that database. Verify snapshot integrity. No new downloads on the search path.
- BLAST: `-taxids` / `-negative_taxids`; pass the snapshot directory first in the child process BLASTDB environment, preserving existing BLASTDB entries. DIAMOND: `--taxonlist` / `--taxon-exclude`. XML output unchanged. The installed engines must support these options (BLAST+ >= 2.15 for higher taxa). Native descendant expansion is performed by the engines. Include/exclude are mutually exclusive.
- Cache key includes resolved filter and database path; changing the filter invalidates displayed results. Search strategy JSON and preferences preserve mode, resolved IDs and snapshot label, omitting the local snapshot directory; a restored strategy is revalidated against the currently selected database's snapshot. Job-report parameters include active filter settings (the report retains the existing current-input-based behavior; full run provenance is deferred). No changes to installer, curated database registration or result annotation in this phase.
- Initial UI uses numeric TaxIDs rather than scientific-name autocomplete. Future lineage and name lookup will share the annotation infrastructure.

## Apply

```sh
git switch feature/taxonomy
git status
unzip ~/Downloads/LocAlignR-taxonomy-phase4.zip -d /tmp/localignr-taxonomy-phase4
git apply --check /tmp/localignr-taxonomy-phase4/LocAlignR-taxonomy-phase4.patch
git apply /tmp/localignr-taxonomy-phase4/LocAlignR-taxonomy-phase4.patch
git diff --check
```

## Test

```sh
conda activate localignr
Rscript scripts/test_taxonomy_backend.R
Rscript -e 'shiny::runApp("inst/app", launch.browser = TRUE)'
```

The expanded smoke test builds temporary databases, verifies native TaxIDs as before, and exercises the actual XML search wrappers with Primates (9443) inclusion/exclusion for human and mouse synthetic proteins, using a non-modal process runner. No production registry changes. The final PASS line includes descendant inclusion/exclusion in XML. Optional unit tests: `Rscript -e 'pkgload::load_all(); testthat::test_dir("tests/testthat", filter="^(taxonomy-search|blast_args|search_strategy)$")'`.

Manual Shiny tests: select a taxonomy-aware local DB; search without filter, with include 9443, exclude 9443, and multiple IDs 9606,10090. Use the Phase 2 synthetic human/mouse FASTA as both query and database, or an actual annotated database. Verify expected hit subjects; invalid/empty/unknown IDs must fail before execution. Switch to a conventional or remote DB while a filter is active and verify it cannot run until None is selected. Repeat a search with changed IDs to confirm no stale cached results. Export/reload a strategy with a filter (including same aligner), then load an older strategy without a filter and check None is restored. Restart and check preferences. Inspect job-report filter settings. The bundled curated Swiss-Prot database will not be marked taxonomy-capable until installer integration or a manual taxonomy-aware build.

R, BLAST and DIAMOND were unavailable in the patch authoring container; tests require local execution. No new dependencies. Name lookup, result annotation, complete run provenance and installer integration remain pending.
