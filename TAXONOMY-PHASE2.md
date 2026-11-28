# LocAlignR taxonomy: phase 2 (registry and indexing backend)

Apply to the `feature/taxonomy` branch after phase 1. This patch is based on the uploaded release-review repository, not a live checkout of your branch. Inspect `git status` first, then run `git apply --check` and `git apply`. Stop on conflicts; do not overwrite local files to force application.

## Changes

- `02_user_db_registry.R`: preserves optional `has_taxonomy`, `taxonomy_source`, `taxonomy_dir`, `taxonomy_snapshot`, `taxonomy_map_path` through normalization, YAML load/save and database selection. Old rows default to no taxonomy. Remote nr/nt do not advertise the local taxonomy capability.
- `07_makeseqdb.R`: adds the optional `taxonomy = NULL` argument to `run_makeseqdb_and_register()`. Existing callers need no changes. Taxonomy-aware builds require a new name, run in a staging directory and publish only on success. Retain canonical and engine-specific mappings alongside the index, plus optional metadata. BLAST v5 uses parsed IDs and validates the indexed TaxID count distribution with blastdbcmd; DIAMOND uses exact ID matching and requires the mapped-sequence count reported by makedb to equal FASTA sequence count.
- `14_taxonomy_build.R`: maps every sequence via UniProt OX fields, a single TaxID, or a TSV with `id` and `taxid` columns. Uses the existing shared taxonomy snapshot, resolves merged IDs and rejects unknown/deleted IDs, duplicate sequence IDs, missing and extraneous mappings. No downloads occur on source().
- `server.R`: sources the two taxonomy modules. No visible Shiny UI controls or search filters yet.
- `scripts/test_taxonomy_backend.R`: real-engine smoke test on synthetic sequences using a temporary registry. Reads/reuses the normal taxonomy snapshot, downloading one only if no valid snapshot is available. Tests conventional BLAST, taxonomic BLAST and DIAMOND, YAML persistence and per-sequence native TaxIDs. Temporary indexes are removed on exit.
- `tests/testthat/test-taxonomy-build.R`: synthetic snapshot and offline unit tests (registry compatibility, three assignment modes, exact IDs, merged/invalid IDs, engine mapping format, DIAMOND count validation).

## Apply and test

From the repository root (change the path to the actual patch location):

```sh
git switch feature/taxonomy
git status
git apply --check ~/Downloads/LocAlignR-taxonomy-phase2.patch
git apply ~/Downloads/LocAlignR-taxonomy-phase2.patch
git diff --check
conda activate localignr
Rscript scripts/test_taxonomy_backend.R
```

Expected last line: `PASS: conventional BLAST, taxonomy BLAST, taxonomy DIAMOND, registry persistence and native TaxIDs.`

If the development environment includes testthat and pkgload, also run `Rscript -e 'pkgload::load_all(); testthat::test_dir("tests/testthat", filter="^(taxonomy-build|registry|resolve_db_selection_matrix)$")'`. The existing test helper uses temporary configuration paths; do not replace those guards. The smoke test does not require testthat. Do not run unit tests against a real registry.

## Programmatic interface for the next UI phase

Supply one of these to the existing builder's optional `taxonomy` parameter:

```r
list(method = "uniprot")
list(method = "single", taxid = "9606")
list(method = "mapping", mapping_path = "/path/to/sequence_taxid.tsv")
```

`taxonomy_dir` can optionally be supplied to pin an existing verified snapshot. Custom TSV must contain the header `id\ttaxid` (actual tab), followed by exact FASTA identifiers and positive NCBI taxonomy IDs. Example:

```text
id	taxid
seq1	9606
seq2	10090
```

A new database built in `outdir` will occupy `outdir/name_backend/` with the `name_backend` prefix and the mapping TSVs. Existing conventional builds retain their original paths. The canonical `sequence_taxid.tsv` stores original FASTA identifiers and resolved TaxIDs; the DIAMOND map intentionally uses full identifiers in both accession columns with `--no-parse-seqids` (not the accession-only convention used in the separately validated curated archive). This prevents normalization collisions for arbitrary user FASTA identifiers. Verify both engines using the smoke test before relying on this backend. BLAST's own identifier parser still imposes its own sequence-ID constraints.

## Scope and limitations

- Complete mapping is required in this first implementation; partially mapped databases are not supported by this backend. A deleted/unknown TaxID causes failure rather than silent omission.
- `has_taxonomy` means a successful native build and recorded capability, not an ongoing integrity check. Later search code must validate the resources are still present and configure BLASTDB for descendant filtering.
- BLAST build validation checks the TaxID multiset; DIAMOND validates the mapped count. The smoke test independently checks both sequences' assignments. No native integration, regression or R parsing tests were executed by the patch author because R and the aligners were not available in the authoring container. `git apply --check`, clean baseline application and `git diff --check` were performed.
- This is source-only: no installer activation, curated DB installation, UI, taxonomic query filters, report changes, or version bump. The existing published installers are untouched. Rebuilding the Conda package is unnecessary for the smoke test.

## Commit after validation

```sh
git add inst/app/R/02_user_db_registry.R inst/app/R/07_makeseqdb.R \
  inst/app/R/14_taxonomy_build.R inst/app/server.R \
  scripts/test_taxonomy_backend.R tests/testthat/test-taxonomy-build.R TAXONOMY-PHASE2.md
git commit -m "Support taxonomy-aware database indexing and registry persistence"
git push
```
