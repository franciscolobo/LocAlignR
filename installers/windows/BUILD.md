# Building the LocAlignR Windows installer

## Compile using GitHub Actions (recommended)

In the LocAlignR repository, run **Actions > Build Windows Installer > Run workflow**. The workflow compiles `LocAlignR.iss` using Inno Setup on a Windows runner and produces the `LocAlignR-Windows-Installer` artifact containing the executable and SHA256SUMS.txt. It does not publish releases automatically. Artifacts expire after 30 days.

For a production build use `Development 0` and `ForcePrivateConda 0`. For an isolated test use `Development 1`; set `ForcePrivateConda 1` only to exercise the private Miniforge bootstrap. Local compilation is also possible using Inno Setup 6.3+ (open LocAlignR.iss and compile).

The runtime is dedicated to the application. The installer downloads official upstream binaries without republishing them. License/documentation files are preserved in the environment. The uninstaller removes the dedicated runtime, optionally removes installer-owned Miniforge, and preserves separately stored databases and registry. Test the production artifact on an unrestricted Windows machine before publication; signing is not yet configured.

## Build the Windows R package only when required

The noarch package `r-localignr-windows` contains the R application but does not depend on Conda-managed BLAST or DIAMOND. Never install it alongside `r-localignr` in the same environment. Synchronize recipe versions with DESCRIPTION; increment the build number before replacing published content at the same version. Do not overwrite existing published archives.

From repository root on Mac:

```bash
conda activate localignr-build
conda-build recipe-windows --no-anaconda-upload --override-channels \
  -c conda-forge -c bioconda -c franciscolobo
PACKAGE_PATH=$(conda-build recipe-windows --output --override-channels \
  -c conda-forge -c bioconda -c franciscolobo)
ls -lh "$PACKAGE_PATH"
```

After successful validation, authenticate on Anaconda.org and upload the exact newly built archive with `anaconda upload --user franciscolobo "$PACKAGE_PATH"`. Do not use the standard recipe build script for this variant.
