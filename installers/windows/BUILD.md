# LocAlignR Windows installer: direct upstream downloads (revision 3)

This patch is for the **LocAlignR** repository, not the independent Windows bioinformatics recipes repository. It adds `recipe-windows/` and replaces the Windows installer sources in `installers/windows/`. The existing `recipe/`, `scripts/build-and-upload.sh`, macOS installer, R application and database manifest are unchanged.

## Why a second recipe?

The existing noarch `r-localignr` package requires `blast` and `diamond` through its Conda runtime metadata. Simply downloading executables would not satisfy that dependency solver. The separate noarch package `r-localignr-windows` contains the same R package (`LocAlignR`), with R dependencies but no alignment-engine dependencies. It is intended only for the Windows installer. Its first build is 0. The installer explicitly requests `vc14_runtime` and `ucrt` on Windows. Never install both R package variants in the same environment.

## Build the Windows installer package on Mac

From the LocAlignR repository root, after copying these directories, confirm `DESCRIPTION` is version 0.2.1. In your existing build environment:

```bash
conda activate localignr-build
conda-build recipe-windows \
    --no-anaconda-upload \
    --override-channels \
    -c conda-forge \
    -c bioconda \
    -c franciscolobo
  
PACKAGE_PATH=$(conda-build recipe-windows --output)
ls -lh "$PACKAGE_PATH"
anaconda upload --user franciscolobo "$PACKAGE_PATH"
```

Select anaconda.org if prompted. The recipe test checks the internal R package version and entry point. The new package does not include the upstream binaries. Do not use the existing `scripts/build-and-upload.sh` for this variant: that script targets `recipe/` and checks Conda-installed engines. Keep the two recipe versions and DESCRIPTION synchronized on future releases. Bump the Windows recipe build number when changing a published archive without changing the version.

## Build and test the installer

Open `installers/windows/LocAlignR.iss` with Inno Setup 6.3+ (7 was used for the previous revision), and compile. The default development installation has a distinct app ID, default directory `%LOCALAPPDATA%\LocAlignR-upstream-test`, and output `LocAlignR-0.2.1-Windows-x86_64-Setup-upstream-test.exe`. It does not require the local Windows Conda channel. Close other LocAlignR instances before installation. The registry is shared across installations; back it up before testing. The existing test installation remains untouched. The optional database task defaults to a new database folder, and uses the same canonical macOS manifest when built in the repository. The fallback manifest snapshot is unchanged.

First test without optional database download. Verify the desktop launcher, database creation, BLAST and DIAMOND alignments, XML parsing and export. Then test optional database provisioning in a new empty destination. Inspect logs if a step fails. The installer uses its own temporary extraction directory, Windows tar, and R already installed in the runtime environment for discovering and copying files. It does not require PowerShell or Python. Upstream archives are fetched directly on the user's computer and checked against the pinned SHA256 values copied from the previously validated Windows recipes. Full BLAST bin contents are copied; DIAMOND executable and sibling DLLs are copied. License and documentation files are kept under `upstream-engine-notices` in the environment. Existing differing files are never overwritten. Conda-managed BLAST/DIAMOND and the old r-localignr variant are rejected to avoid mixed installations. Unmanaged engine files may remain after Conda environment removal; inspect the dedicated test prefix and remove only installer-owned files if necessary. The optional databases and shared registry are intentionally retained.

After validating this development variant, production mode is selected with `#define Development 0` in LocAlignR.iss. Do not switch until clean installation, bootstrap, upgrade/uninstall behavior and signing have been tested. This is a source patch, not a compiled installer. No Windows execution or compilation was performed in the authoring environment. Direct-download distribution avoids hosting upstream engine archives or binaries, but does not waive their license terms. Do not embed, mirror or upload engine binaries as part of this distribution.
