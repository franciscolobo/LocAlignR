# Build automation

LocAlignR distributes two Conda packages containing the same R application: `r-localignr` for macOS/Linux (with Conda-managed alignment engines) and `r-localignr-windows` for the Windows installer (engines downloaded directly from upstream). Do not install both in one environment.

## Standard package

Use the validated local script `scripts/build-and-upload.sh` from the repository root. See its `--help` for supported arguments. For a same-version update, bump the build number and first build/test without uploading:

```bash
bash scripts/build-and-upload.sh --bump-build --skip-upload
```

Review the reported archive and validation output. Use `--skip-build --package-path /absolute/path/to/archive` to validate and upload that exact archive when ready. Keep `DESCRIPTION` and both recipe versions synchronized. Inspect the actual package name, version and build number; never overwrite a published archive. Credentials should be kept outside Git (e.g. interactive Anaconda.org login or an authorized API token in the ignored `.env` file). Do not disable TLS verification.

The legacy `.github/workflows/build-conda.yml` is retained for manual use only; its automatic tag trigger has been removed and uploads default to disabled. Its older runner and build-tool configuration has not been revalidated; use the tested local script for releases until the legacy workflow is modernized.

## Windows package and installer

See [Windows BUILD.md](../installers/windows/BUILD.md). The manual **Build Windows Installer** GitHub Actions workflow compiles the committed installer source and produces a downloadable artifact and checksum. It does not publish to Anaconda.org or GitHub Releases.

## macOS installer

On macOS, run `zsh installers/macos/build_installer.sh` from the repository root. It creates the script-based installer app and the two ZIP filenames in `installers/macos/dist/`. Both ZIPs package the same script-based app; its bootstrap selects the target architecture at installation time. The current installer resolves the standard Conda package by name rather than pinning the version. Verify the installed version during release testing.

## Release procedure

Review the version, license and dependencies; validate the Conda archives; compile both desktop installers; verify checksums; test installation and uninstallation; create a draft GitHub release with the validated artifacts and release notes. Publish only after reviewing the exact downloadable files. Keep GitHub Actions artifacts separately until publication because they expire.
