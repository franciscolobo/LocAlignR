# Installation

This document describes how to install **LocAlign** and its dependencies on Linux, macOS, and Windows.

LocAlign is a local Shiny application and requires:
- R and R packages
- External alignment tools (BLAST+, optionally DIAMOND)

The recommended installation method uses **conda/micromamba** for external tools and **renv** for R dependencies.

---

## System requirements

- Operating system: Linux, macOS, or Windows
- R >= 4.2
- Internet access for initial installation
- Sufficient disk space for local BLAST databases

---

## 1. Clone the repository

git clone https://github.com/<your-username>/LocAlign.git
cd LocAlign

## 2. Install BLAST using conda or micromamba (recommended)

Create a dedicated environment for external tools:

conda create -n localign-tools -c conda-forge -c bioconda blast


or, with micromamba:

micromamba create -n localign-tools -c conda-forge -c bioconda blast


Activate the environment:

conda activate localign-tools
 or
micromamba activate localign-tools


Verify installation:

blastp -version
makeblastdb -version

## 3. Configure environment variables (optional but recommended)

LocAlign can detect BLAST on PATH, but environment variables provide explicit control.

Linux / macOS
export LOCALIGN_BLASTP="$(which blastp)"
export LOCALIGN_BLASTN="$(which blastn)"
export LOCALIGN_MAKEBLASTDB="$(which makeblastdb)"


To make this persistent, add the lines above to ~/.bashrc or ~/.zshrc.

Windows (PowerShell)
setx LOCALIGN_BLASTP (Get-Command blastp).Source
setx LOCALIGN_BLASTN (Get-Command blastn).Source
setx LOCALIGN_MAKEBLASTDB (Get-Command makeblastdb).Source


Restart the terminal after running setx.

## 4. Install R dependencies

From the repository root:

R -e "install.packages('renv'); renv::restore()"


This installs all required R packages using the versions pinned in renv.lock.

## 5. Run the application

Activate the conda environment (if not already active):

conda activate localign-tools


Launch LocAlign:

shiny::runApp("app")


The application should open in your default web browser.

## 6. BLAST databases

LocAlign does not ship with BLAST databases.

You must either:

Use remote databases (nr, nt), or

Build local databases using makeblastdb

See docs/databases.md for instructions on building and managing local databases.

## 7. Troubleshooting

If BLAST is not detected, verify:

The conda environment is activated

blastp and makeblastdb are on PATH

LOCALIGN_* environment variables point to valid executables

On Windows, ensure antivirus software is not blocking BLAST executables.

For permission issues on macOS or Linux, check file execution permissions.

## 8. Optional components

DIAMOND support can be added by installing diamond in the same conda environment.

A Docker-based setup may be provided for fully isolated execution.

## Getting help

If installation fails:

Check the output of Rscript scripts/check_install.R

Open a GitHub issue with your OS, R version, and error messages
