# LocAlignR 0.2.1

LocAlignR provides an interactive interface for biological sequence alignment, database management and result exploration using BLAST and DIAMOND.

## Highlights

- Windows installer with automatic Conda provisioning, official upstream BLAST+ and DIAMOND downloads, checksum verification, progress reporting and dedicated-runtime uninstallation.
- macOS installer and Conda-based distribution for macOS and Linux.
- BLAST and DIAMOND search configuration, advanced parameters, local database creation and backend-aware database registry.
- Optional UniProtKB/Swiss-Prot reference database provisioning through the desktop installers.
- Interactive alignment results and exports to HTML, Excel and XML; reusable JSON search strategies and YAML job reports.
- Diagnostics for external alignment engines and runtime environment.

## Installation

See the [installation guide](installation.md). Internet access is required for initial installation and optional reference database provisioning. Local searches can subsequently run offline.

## Known limitations

- Windows installer is unsigned. Microsoft Defender SmartScreen or institutional security policies may warn or block execution. Contact IT when required.
- DIAMOND supports protein databases; select BLAST for nucleotide database searches.
- Selecting remote BLAST databases `nr` or `nt` sends query sequences to NCBI. Use local databases for private/offline analyses.

## License

MIT; external software retains its own licensing terms.
