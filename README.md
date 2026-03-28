# LocAlign

**LocAlign** is a local, offline Shiny application for biological sequence alignment.  
It provides a graphical interface to run **BLAST** and **DIAMOND** on your own machine, without uploading data to external servers.

LocAlign is designed for reproducible research, local database usage, and environments where data privacy or limited connectivity are important.

LocAlign was inspired by Shiny_BLAST: https://github.com/ScientistJake/Shiny_BLAST

---

## Features

- Local sequence alignment using:
  - BLAST+ (nucleotide and protein)
  - DIAMOND (fast protein alignments)
- Shiny-based interactive interface
- Support for custom, user-built databases
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

LocAlign is designed to be installed and run inside a conda environment that provides
BLAST, DIAMOND, and all required R dependencies.

See:

docs/installation.md

for a fully reproducible installation procedure, including exact channel configuration.

---

## Running LocAlign

After installation, launch LocAlign from R:

```r
LocAlign::run_app()
```

This will start the Shiny application locally and open it in your browser.

## Databases

LocAlign does not ship with alignment databases.

### User-provided databases

You may create your own BLAST or DIAMOND databases locally.

The application includes functionality to build them.

For guidance:

See the Build database panel in the application

Or consult the documentation in docs/

### Curated reference databases (optional)

LocAlign also provides access to a small, non-redundant set of curated reference databases with representative homolog sets across major taxonomic groups.

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

## Configuration

LocAlign uses two levels of configuration:

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

 - LocAlign::run_app()

 - versioning

 - citation support

- Developer-only tooling (e.g. renv) is kept under dev/ and is optional

---

## Project status

LocAlign is under active development.

Interfaces, workflows, and configuration options may evolve, but releases will be
tagged and versioned.

---

## Citation

If you use LocAlign in academic work, please cite it using the information in:

- CITATION.cff (GitHub / general use)

- citation("LocAlign") from within R

---

## License

LocAlign is released under the MIT License.

See the LICENSE file for details.

---

## Contact and contributions

For bug reports, feature requests, or questions, please open an issue on GitHub.

Contributions are welcome.

See CONTRIBUTING.md for guidelines.
