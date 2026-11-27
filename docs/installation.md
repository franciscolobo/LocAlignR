# Installation and troubleshooting

## Windows

Use the Windows x86-64 installer from [GitHub Releases](https://github.com/franciscolobo/LocAlignR/releases). Windows 10 version 1809 or later and Windows 11 are the intended targets. Internet access and sufficient local disk space are required. The installer runs without elevation, subject to local IT policy.

The installer creates `%LOCALAPPDATA%\LocAlignR\envs\localignr`, reuses Conda when available or installs private Miniforge under the application directory, installs `r-localignr-windows=0.2.1`, and provisions official BLAST+ 2.17.0 and DIAMOND 2.2.8 directly from upstream. The optional curated database is downloaded and formatted separately. The installer verifies upstream archive checksums.

### Verify and launch

Open LocAlignR using its Start menu entry or optional desktop shortcut. The Diagnostics tab reports detected engine paths and versions. If installation fails, inspect the Inno Setup log in `%TEMP%` (look for `Setup Log ... .txt`).

To verify the downloaded installer checksum in PowerShell, from the extracted download directory:

```powershell
Get-FileHash -Algorithm SHA256 -Path .\LocAlignR-0.2.1-Windows-x86_64-Setup.exe
Get-Content .\SHA256SUMS.txt
```

Compare the hashes for the same filename. A checksum does not substitute for a trusted signature. The current installer is unsigned; on managed machines, request IT approval if SmartScreen blocks it. Do not disable security protections.

### Uninstall

Close LocAlignR, then select LocAlignR in Windows Settings > Apps > Installed apps > Uninstall. Alternatively run `%LOCALAPPDATA%\LocAlignR\unins000.exe` if present. The uninstaller removes the dedicated runtime and offers to remove installer-owned private Miniforge. It preserves external Conda installations and separately stored databases and registry. Back up data before uninstalling.

## macOS

Use the macOS installer archive from GitHub Releases. Extract it and open **LocAlignR Installer.app**; follow the Terminal prompts. The same script-based installer supports Apple Silicon and Intel and selects the appropriate Miniforge bootstrap when needed. It installs a named `localignr` Conda environment and can create a launcher in `~/Applications/LocAlignR.app`. Existing Conda is reused when detected. No administrator privileges are normally needed for user-local installation.

If a managed computer blocks the app, consult IT. For runtime errors, inspect the Terminal output and, if a launcher was created, `~/Library/Logs/LocAlignR/launcher.log`.

To uninstall a dedicated macOS runtime, close LocAlignR and confirm the environment is not shared, then run `conda env remove -n localignr`. Remove the LocAlignR launcher from `~/Applications` if desired. Preserve any databases, configuration and Conda installations you still need.

## Linux and manual macOS installation

Install [Miniforge](https://github.com/conda-forge/miniforge) if Conda is not available. Create a fresh named environment without changing global channel configuration:

```bash
conda create -n localignr -y --override-channels --strict-channel-priority \
  -c conda-forge -c bioconda -c franciscolobo \
  r-localignr=0.2.1 r-jsonlite
conda activate localignr
blastp -version
makeblastdb -version
diamond version
R -e 'LocAlignR::run_app()'
```

The package installs R, required R packages and alignment engines. The explicit `r-jsonlite` requirement covers the current published recipe's missing direct dependency. Do not install the two LocAlignR Conda variants in the same environment.

## Tool discovery and configuration

LocAlignR checks `PATH` first. If a tool cannot be found there, it can use a corresponding environment variable: `LOCALIGN_BLASTP`, `LOCALIGN_BLASTN`, `LOCALIGN_BLASTX`, `LOCALIGN_TBLASTN`, `LOCALIGN_TBLASTX`, `LOCALIGN_MAKEBLASTDB` or `LOCALIGN_DIAMOND`. These are normally unnecessary.

The Diagnostics tab reports the detected paths. User preferences and the database registry reside in the platform-specific R user configuration directory. Obtain it in R with:

```r
tools::R_user_dir("LocAlignR", "config")
LocAlignR::localignr_log_file()
```

Review logs before sharing them. Use local registered databases for offline/private searches; selecting remote BLAST `nr` or `nt` sends queries to NCBI.
