# Taxonomy development: staged manifest and shared resource manager

Apply to the feature/taxonomy branch. This patch adds new files only. The two active installer manifests and the production installer code remain untouched, because the Windows reader currently accepts only schema 1.0 and exactly two archive outputs.

The candidate manifest `inst/extdata/db_manifest-taxonomy.json` describes the November 27, 2026 Swiss-Prot archive and a shared NCBI taxonomy resource set. `taxonomy.enabled` describes the dataset capability, not an already indexed database. The new schema is a development contract, not yet consumed by either installer.

## Check the curated archive

From the repository root:

```bash
python scripts/validate_taxonomy_archive.py /path/to/uniprot_sprot_11_27_2026.tar.gz
```

The validator accepts exactly the four expected nonempty regular files, either at the archive root or inside the single named dataset directory. It rejects unexpected members, including macOS AppleDouble files. If validation fails, inspect the archive rather than changing the published checksum arbitrarily.

## Test the taxonomy resource manager

Use the existing LocAlignR Conda environment (with digest and jsonlite installed):

```r
source('inst/app/R/13_taxonomy.R')
root <- file.path(tempdir(), 'localignr-taxonomy-test')
p <- localignr_taxonomy_ensure(root = root)
print(p)
print(list.files(p))
stopifnot(localignr_taxonomy_validate(p))
stopifnot(identical(p, localignr_taxonomy_ensure(root = root)))
```

The default persistent path is `tools::R_user_dir('LocAlignR', 'data')/taxonomy`. The manager downloads NCBI archives over HTTPS, requires matching upstream MD5 sidecars, calculates local SHA-256 fingerprints, retains only the seven required resources and a provenance manifest, and cleans temporary files on success or error. No download occurs merely by sourcing the module. A refresh (`refresh = TRUE`) creates a new snapshot; old snapshots remain available. The download timestamps identify retrieval, not a guaranteed common NCBI release date. The two upstream resources may have different publication dates.

The upstream MD5 values are transfer integrity checks, not digital signatures. The BLAST MD5 sidecar could not be fetched in the review environment; the live test must confirm it is reachable. There is intentionally no silent unverified fallback.

No registry, index-building, UI, BLASTDB environment configuration or installer changes are included yet. The manifest's format options will be consumed in the next implementation stage. Do not copy the candidate over active installer manifests until the readers are updated.
