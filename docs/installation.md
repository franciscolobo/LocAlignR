# Installation

LocAlign is distributed primarily as a conda package. This guarantees that all system-level dependencies (BLAST, DIAMOND, R, and R packages) are installed consistently across Linux, macOS, and Windows.

---

## Prerequisites

- A working conda installation (Miniconda or Mambaforge recommended)
- Operating system: Linux, macOS, or Windows
- R >= 4.2
- Internet access for initial installation
- Sufficient disk space for local BLAST/DIAMOND databases

---

## Conda

Check conda is available:

conda --version

### Recommended: clean environment (fully reproducible)

Create a dedicated environment for LocAlign:

conda create -n localign -y
conda activate localign

### Required channels (critical)

LocAlign depends on:

- conda-forge for R and R packages

- bioconda for BLAST and DIAMOND

Channel order matters and must be:

1) conda-forge

2) bioconda

3) defaults

Set this once:

conda config --add channels defaults
conda config --add channels bioconda
conda config --add channels conda-forge
conda config --set channel_priority strict


Verify:

conda config --show channels


Expected order:

channels:
  - conda-forge
  - bioconda
  - defaults

---

## Install LocAlign

Install LocAlign using explicit channels to ensure reproducibility:

conda install --override-channels \
  -c conda-forge \
  -c bioconda \
  -c defaults \
  r-localign


This will install:

- LocAlign (R package)

- R (via conda-forge)

- BLAST+ (via bioconda)

- DIAMOND (via bioconda)

- All required R dependencies

---

## Verify installation

### Check BLAST availability
blastp -version
makeblastdb -version

Both commands should return version information.

### Check DIAMOND availability
diamond version

### Launch LocAlign
R -e "LocAlign::run_app()"


The Shiny application should open in your browser.

### Notes on environment variables (optional)

By default, LocAlign discovers tools from the active conda environment (PATH).

Advanced users may override tool paths using environment variables:

LOCALIGN_BLASTP

LOCALIGN_BLASTN

LOCALIGN_BLASTX

LOCALIGN_TBLASTN

LOCALIGN_MAKEBLASTDB

LOCALIGN_DIAMOND

Example:

export LOCALIGN_MAKEBLASTDB=/custom/path/makeblastdb


This is **not required** for standard conda installs.

---

## Platform-specific notes

### macOS (Apple Silicon)

All dependencies are provided via conda-forge and bioconda. No Rosetta setup is required.

### Windows

Use the conda prompt (Anaconda Prompt or Miniforge Prompt). All tools are installed as .exe binaries and are automatically detected.

---

## Troubleshooting

If installation fails:

1) Confirm channel order:

conda config --show channels


2) Retry install with explicit channels:

conda install --override-channels \
  -c conda-forge -c bioconda -c defaults r-localign


3) Ensure the environment is activated:

conda activate localign

---

## Alternative installation methods

Installing LocAlign without conda is not recommended and is unsupported for full functionality, as BLAST and DIAMOND must be available on PATH.

This installation procedure is fully reproducible and is the only supported installation method for LocAlign.

