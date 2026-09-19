# LocAlignR

**LocAlignR** is a local, offline Shiny application for biological sequence alignment.  
It provides a graphical interface to run **BLAST** and **DIAMOND** on your own machine, without uploading data to external servers.

LocAlignR is designed for reproducible research, local database usage, and environments where data privacy or limited connectivity are important.

LocAlignR was inspired by Shiny_BLAST: https://github.com/ScientistJake/Shiny_BLAST

---

## Features

- Local sequence alignment using:
  - BLAST+ (nucleotide and protein)
  - DIAMOND (fast protein alignments)
- Shiny-based interactive interface
- Support for custom, user-built databases
- Export full alignment results as an interactive HTML report, a formatted Excel spreadsheet, or raw XML
- Save and reload search configurations (JSON), and export job summary reports (YAML)
- Fully offline operation after installation
- Cross-platform: Linux, macOS, and Windows
- Conda-based installation for external tools
- Built-in **Diagnostics** tab for tool and environment checks

---

## Requirements

- R (>= 4.2 recommended)
- BLAST+ and DIAMOND available on `PATH`
- Supported operating systems:
  - Linux
  - macOS (Intel and Apple Silicon)
  - Windows

The recommended and supported way to install BLAST and DIAMOND is via **conda**.

---

## Installation

### Conda-based installation (recommended)

LocAlignR is designed to be installed and run inside a conda environment that provides
BLAST, DIAMOND, and all required R dependencies.

See:

docs/installation.md

for a fully reproducible installation procedure, including exact channel configuration.

---

## Running LocAlignR

After installation, launch LocAlignR from R:

```r
LocAlignR::run_app()
```

This will start the Shiny application locally and open it in your browser.

## Databases

LocAlignR does not ship with alignment databases.

### User-provided databases

You may create your own BLAST or DIAMOND databases locally.

The application includes functionality to build them.

For guidance:

See the Build database panel in the application

Or consult the documentation in docs/

### Curated reference databases (optional)

LocAlignR also provides access to a small, non-redundant set of curated reference databases with representative homolog sets across major taxonomic groups.

These databases are:

- Hosted externally on Zenodo

- Downloaded on demand from within the application interface

- Stored locally on the user’s machine

- Formatted locally using BLAST (makeblastdb) or DIAMOND tools

This approach avoids shipping large data files with the application while ensuring:

- Reproducibility

- Transparent provenance

- Full offline use after download

Downloaded databases can be reused across sessions and configured once.

---

## Results and exports

Once an alignment run completes, results are shown in an interactive, filterable
table, with per-hit metadata (when available) and alignment detail on row click.

Several export options are available from the **Downloads** section of the run
panel. These fall into two distinct categories — full alignment results, and
records of how a search was configured/run — which is important to keep in
mind since they are not interchangeable:

**Full alignment results** (every hit, with sequences/coordinates):

| Format | Contents |
| --- | --- |
| HTML report | Self-contained, interactive results table with hover tooltips showing metadata and full alignments |
| Excel spreadsheet | Formatted `.xlsx` workbook with all hits, joined metadata columns, and per-hit alignment text |
| XML | Raw BLAST/DIAMOND XML output, for reuse in other tools or pipelines |

**Search configuration and run records** (no hit-level data):

| Format | Contents |
| --- | --- |
| Search strategy | JSON file capturing only the aligner, program, database, e-value, preset, and parameters used — no results. Intended to be reloaded via "Load strategy" to repeat the exact same search later, or to share a search setup with collaborators |
| Job report | YAML file recording the search configuration, the database used, and a brief summary (hit count, top hit, top bit score, top e-value) — not the full hit table. Useful for keeping a record of what was run and its headline outcome, alongside one of the full-results exports above |

---

## Configuration

LocAlignR uses two levels of configuration:

- **Default, read-only configuration** bundled with the app

- **User-specific configuration** stored in an OS-appropriate location

For advanced users, external tool paths can be controlled via environment variables if needed:

- LOCALIGN_BLASTP

- LOCALIGN_BLASTN

- LOCALIGN_MAKEBLASTDB

- LOCALIGN_DIAMOND

The Diagnostics tab reports which tools are detected and which paths are in use.

---

## Development notes

- A minimal R package wrapper is used to provide:

 - LocAlignR::run_app()

 - versioning

 - citation support

- Developer-only tooling (e.g. renv) is kept under dev/ and is optional

---

## Project status

LocAlignR is under active development.

Interfaces, workflows, and configuration options may evolve, but releases will be
tagged and versioned.

---

## Citation

If you use LocAlignR in academic work, please cite it using the information in:

- CITATION.cff (GitHub / general use)

- citation("LocAlignR") from within R

---

## License

LocAlignR is released under the MIT License.

See the LICENSE file for details.

---

## Contact and contributions

For bug reports, feature requests, or questions, please open an issue on GitHub.

Contributions are welcome.

See CONTRIBUTING.md for guidelines.
