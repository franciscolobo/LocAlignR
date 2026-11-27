# Windows installer

LocAlignR uses `r-localignr-windows` and downloads official BLAST+ 2.17.0 and DIAMOND 2.2.8 at installation time, verifying their SHA-256 checksums. No custom Conda channel for native alignment engines is required. See [BUILD.md](BUILD.md) for developer instructions and [user installation documentation](../../docs/installation.md) for installation and uninstallation.

The production installer uses `%LOCALAPPDATA%\LocAlignR`. Development builds use `%LOCALAPPDATA%\LocAlignR-upstream-test` and a separate application identifier. The canonical database manifest is `../macos/payload/db_manifest.json` (the local snapshot is a fallback).
