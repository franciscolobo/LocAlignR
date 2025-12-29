# LocAlign

**LocAlign** is a local, offline Shiny application for sequence alignment.  
It provides a graphical interface to run **BLAST** and **DIAMOND** on your own machine, without uploading data to external servers.

LocAlign is designed for reproducible research, local database usage, and environments where data privacy or limited connectivity are important.

---

## Features

- Local sequence alignment using:
  - BLAST+ (nucleotide and protein)
  - DIAMOND (fast protein alignments)
- Shiny-based interactive interface
- Support for custom, user-built databases
- Fully offline operation after installation
- Cross-platform: Linux, macOS, and Windows
- Reproducible R environment via `renv`

---

## Requirements

- R (>= 4.2 recommended)
- BLAST+ and DIAMOND installed locally
- Supported operating systems:
  - Linux
  - macOS (Intel and Apple Silicon)
  - Windows

The recommended way to install BLAST and DIAMOND is via micromamba/conda.

---

## Installation (Quick Start)

### 1. Clone the repository

git clone https://github.com/<your-org>/LocAlign.git
cd LocAlign

### 2. Install external tools (BLAST and DIAMOND)

micromamba create -f tools/environment.yml -n localign-tools
micromamba activate localign-tools

### 3. Restore R dependencies

R -e "install.packages('renv'); renv::restore()"

### 4. Verify the installation

Rscript scripts/check_install.R


## Running the app

Rscript app/app.R

Or from an R session:

shiny::runApp("app")

## Databases

LocAlign does not ship with alignment databases.

You must create your own BLAST or DIAMOND databases locally.

See:

docs/databases.md for detailed instructions

scripts/make_blast_db.R

scripts/make_diamond_db.R

## Configuration

Optional configuration can be provided via YAML files in config/.

config/default.yml contains defaults

config/example.local.yml shows how to override tool paths and settings

Environment variables can also be used:

LOCALIGN_BLASTP

LOCALIGN_BLASTN

LOCALIGN_MAKEBLASTDB

LOCALIGN_DIAMOND

## Reproducibility

R package versions are pinned via renv.lock

External tool versions are controlled via tools/environment.yml

Each release will be tagged and archived for citation

## Project status

LocAlign is under active development.
The interface, configuration schema, and default workflows may change.

## Citation

If you use LocAlign in academic work, please cite it using the information in CITATION.cff.

## License

See the LICENSE file for details.

## Contact

For questions, bug reports, or feature requests, please open an issue on GitHub.
