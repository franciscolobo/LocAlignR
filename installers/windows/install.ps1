<# 
LocAlign Windows installer scaffold (PowerShell)

Design goals:
- Conda-first, cross-platform aligned
- No admin required (user-level install)
- Mirrors macOS installer phases
- Uses PATH-based tool discovery; env vars are optional overrides

Usage examples:
  powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1
  powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -EnvName localign -UseMicromamba
#>

[CmdletBinding()]
param(
  [string]$EnvName = "localign",
  [switch]$UseMicromamba,
  [switch]$ForceRecreate,
  [switch]$SetUserEnvVars
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) { Write-Host "[INFO]  $msg" }
function Write-Warn([string]$msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err ([string]$msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-Cmd([string]$name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  return $null -ne $cmd
}

function Assert-RepoRoot {
  if (-not (Test-Path -LiteralPath ".\DESCRIPTION")) {
    throw "Run this script from the LocAlign repository root (DESCRIPTION not found)."
  }
}

function Resolve-CondaFrontend {
  # Decide which frontend to use: micromamba or conda
  if ($UseMicromamba) {
    if (-not (Test-Cmd "micromamba")) {
      throw "micromamba not found on PATH. Install micromamba or run without -UseMicromamba to use conda."
    }
    return "micromamba"
  } else {
    if (-not (Test-Cmd "conda")) {
      throw "conda not found on PATH. Install Miniconda/Miniforge or run with -UseMicromamba."
    }
    return "conda"
  }
}

function Get-CondaActivateCommand([string]$frontend) {
  # Returns a command prefix that runs inside the environment without needing to 'activate' the shell session.
  # This avoids PowerShell activation edge cases.
  if ($frontend -eq "micromamba") {
    return "micromamba run -n $EnvName"
  }
  # conda: use "conda run -n <env>"
  return "conda run -n $EnvName"
}

function Ensure-Env([string]$frontend) {
  Write-Info "Ensuring environment '$EnvName' exists (frontend: $frontend)."

  if ($frontend -eq "micromamba") {
    $envList = & micromamba env list
    $exists = $envList | Select-String -Pattern "^\s*$EnvName\s" -Quiet
    if ($exists -and $ForceRecreate) {
      Write-Warn "Removing existing environment '$EnvName' (ForceRecreate)."
      & micromamba env remove -n $EnvName -y | Out-Null
      $exists = $false
    }
    if (-not $exists) {
      Write-Info "Creating environment '$EnvName'."
      & micromamba create -n $EnvName -c conda-forge -c bioconda -y | Out-Null
    }
  } else {
    $envList = & conda env list
    $exists = $envList | Select-String -Pattern "^\s*$EnvName\s" -Quiet
    if ($exists -and $ForceRecreate) {
      Write-Warn "Removing existing environment '$EnvName' (ForceRecreate)."
      & conda env remove -n $EnvName -y | Out-Null
      $exists = $false
    }
    if (-not $exists) {
      Write-Info "Creating environment '$EnvName'."
      & conda create -n $EnvName -c conda-forge -c bioconda -y | Out-Null
    }
  }
}

function Install-Dependencies([string]$frontend) {
  Write-Info "Installing dependencies into '$EnvName'."
  # Keep the list aligned with macOS installer.
  # Important: On Windows, NCBI BLAST+ is provided by 'blast' on bioconda.
  # DIAMOND package name is 'diamond' on bioconda.

  $pkgs = @(
    "r-base",
    "r-devtools",
    "r-shiny",
    "r-rappdirs",
    "blast",
    "diamond"
  )

  if ($frontend -eq "micromamba") {
    & micromamba install -n $EnvName -c conda-forge -c bioconda -y @pkgs | Out-Null
  } else {
    & conda install -n $EnvName -c conda-forge -c bioconda -y @pkgs | Out-Null
  }
}

function Install-LocAlignPackage([string]$frontend) {
  Write-Info "Installing LocAlign (R package) into the environment."
  $runPrefix = Get-CondaActivateCommand $frontend

  # Use R CMD INSTALL to mirror conda recipe behavior and minimize surprises.
  # Windows paths: use the current directory (repo root).
  $repoPath = (Get-Location).Path

  & $runPrefix R CMD INSTALL $repoPath --no-multiarch | Out-Null
}

function Optionally-SetUserEnvVars([string]$frontend) {
  if (-not $SetUserEnvVars) {
    Write-Info "Skipping LOCALIGN_* env var setup (PATH-based discovery is preferred)."
    return
  }

  Write-Info "Setting user-level LOCALIGN_* env vars (optional overrides)."

  $runPrefix = Get-CondaActivateCommand $frontend

  # Resolve tool paths inside the env. We use where.exe to find the first hit.
  $blastp = (& $runPrefix where.exe blastp.exe 2>$null | Select-Object -First 1)
  $makeblastdb = (& $runPrefix where.exe makeblastdb.exe 2>$null | Select-Object -First 1)
  $diamond = (& $runPrefix where.exe diamond.exe 2>$null | Select-Object -First 1)

  if ($blastp)      { [Environment]::SetEnvironmentVariable("LOCALIGN_BLASTP", $blastp, "User") }
  if ($makeblastdb) { [Environment]::SetEnvironmentVariable("LOCALIGN_MAKEBLASTDB", $makeblastdb, "User") }
  if ($diamond)     { [Environment]::SetEnvironmentVariable("LOCALIGN_DIAMOND", $diamond, "User") }

  Write-Info "Env vars written to User scope. New terminals will see them."
}

function Run-Checks([string]$frontend) {
  Write-Info "Running LocAlign checks."
  $runPrefix = Get-CondaActivateCommand $frontend

  # Your repository already has scripts/check_install.R.
  & $runPrefix Rscript .\scripts\check_install.R
}

function Print-LaunchInstructions([string]$frontend) {
  $runPrefix = Get-CondaActivateCommand $frontend
  Write-Host ""
  Write-Info "Installation complete."
  Write-Host "To run LocAlign:"
  Write-Host "  $runPrefix R -e `"LocAlign::run_app()`""
  Write-Host ""
}

# ---- Main ----
Assert-RepoRoot
$frontend = Resolve-CondaFrontend
Ensure-Env $frontend
Install-Dependencies $frontend
Install-LocAlignPackage $frontend
Optionally-SetUserEnvVars $frontend
Run-Checks $frontend
Print-LaunchInstructions $frontend
