; Compile with Inno Setup 6.3+ or 7. No PowerShell required.
; Default build uses an isolated upstream-download test installation. Set Development to 0 for release.
#define Development 1
#define AppVersion "0.2.1"
#if Development
  #define AppTitle "LocAlignR (Upstream Download Test)"
  #define AppFolder "LocAlignR-upstream-test"
  #define AppIdentifier "LocAlignR-Windows-Upstream-Test"
  #define OutputName "LocAlignR-0.2.1-Windows-x86_64-Setup-upstream-test"
#else
  #define AppTitle "LocAlignR"
  #define AppFolder "LocAlignR"
  #define AppIdentifier "LocAlignR-Windows"
  #define OutputName "LocAlignR-0.2.1-Windows-x86_64-Setup"
#endif
; Prefer the canonical manifest when these files are placed in installers/windows.
#if FileExists(SourcePath + "..\macos\payload\db_manifest.json")
  #define ManifestSource "..\macos\payload\db_manifest.json"
#else
  #define ManifestSource "db_manifest.json"
#endif
[Setup]
AppId={#AppIdentifier}
AppName={#AppTitle}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\{#AppFolder}
DefaultGroupName={#AppTitle}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.17763
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
OutputDir=output
OutputBaseFilename={#OutputName}
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
UninstallLogging=yes
CloseApplications=no
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
Name: curated; Description: "Download curated protein databases and format for BLAST and DIAMOND"; Flags: unchecked
[Files]
Source: "{#ManifestSource}"; DestName: "db_manifest.json"; Flags: dontcopy
Source: "manifest_registry.R"; Flags: dontcopy
Source: "check_install.R"; Flags: dontcopy
Source: "install_engines.R"; Flags: dontcopy
Source: "launch.R"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\{#AppTitle}"; Filename: "{cmd}"; Parameters: "/D /C """"{app}\launch.cmd"""""; WorkingDir: "{app}"
Name: "{userdesktop}\{#AppTitle}"; Filename: "{cmd}"; Parameters: "/D /C """"{app}\launch.cmd"""""; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{cmd}"; Parameters: "/D /C """"{app}\launch.cmd"""""; Description: "Launch LocAlignR"; Flags: postinstall nowait skipifsilent unchecked
[UninstallDelete]
Type: files; Name: "{app}\launch.cmd"
Type: files; Name: "{app}\conda-path.txt"
Type: dirifempty; Name: "{app}\envs"
[Code]
const
  MFURL = 'https://github.com/conda-forge/miniforge/releases/download/25.3.1-0/Miniforge3-25.3.1-0-Windows-x86_64.exe';
  MFSHA = 'b7706a307b005fc397b70a244de19129100906928abccd5592580eb8296fb240';
  BLASTURL = 'https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.17.0/ncbi-blast-2.17.0+-x64-win64.tar.gz';
  BLASTSHA = 'ccde8788641e8f4137536aaadedfeac2f3599dbbc6166e701b5d89d19fa79038';
  DIAMONDURL = 'https://github.com/bbuchfink/diamond/releases/download/v2.2.8/diamond-windows.zip';
  DIAMONDSHA = '8035ece14562e13576da6e9583c74ab1aaff9d0c96086d93ab337e95cd288ce1';
var
  CondaExe, EnvPrefix: String;
  DBPage: TInputDirWizardPage;
  DownloadPage: TDownloadWizardPage;
  Prepared: Boolean;

function Q(const S: String): String;
begin
  Result := '"' + S + '"';
end;

procedure RunChecked(const Exe, Args, WorkDir: String);
var RC: Integer;
begin
  Log('Executing: ' + Exe + ' ' + Args);
  if not ExecAndLogOutput(Exe, Args, WorkDir, SW_HIDE, ewWaitUntilTerminated, RC, nil) then
    RaiseException('Cannot start ' + Exe + ': ' + SysErrorMessage(RC));
  if RC <> 0 then
    RaiseException(Exe + ' exited with code ' + IntToStr(RC) + '. See the installation log for details.');
end;

procedure SetStage(const S: String);
begin
  WizardForm.PreparingLabel.Caption := S + #13#10 + #13#10 +
    'Please wait. This step may take several minutes.';
  Log(S);
end;

procedure RunEnv(const Args: String);
begin
  RunChecked(CondaExe, 'run --prefix ' + Q(EnvPrefix) + ' --no-capture-output ' + Args, ExpandConstant('{app}'));
end;

function ExistingConda(): String;
var P: String;
begin
  Result := '';
  P := GetEnv('CONDA_EXE');
  if FileExists(P) then begin Result := P; Exit; end;
  P := ExpandConstant('{commonappdata}\anaconda3\Scripts\conda.exe');
  if FileExists(P) then begin Result := P; Exit; end;
  P := GetEnv('USERPROFILE') + '\miniforge3\Scripts\conda.exe';
  if FileExists(P) then begin Result := P; Exit; end;
  P := GetEnv('USERPROFILE') + '\miniconda3\Scripts\conda.exe';
  if FileExists(P) then begin Result := P; Exit; end;
  P := GetEnv('USERPROFILE') + '\anaconda3\Scripts\conda.exe';
  if FileExists(P) then begin Result := P; Exit; end;
end;

procedure InitializeWizard();
begin
  DBPage := CreateInputDirPage(wpSelectTasks, 'Database location',
    'Choose a folder for curated databases',
    'Databases are stored separately and are preserved when LocAlignR is uninstalled.', False, '');
  DBPage.Add('');
  DBPage.Values[0] := ExpandConstant('{localappdata}\{#AppFolder}-databases');
  DownloadPage := CreateDownloadPage('Downloading files', 'Please wait while the requested files are downloaded.', nil);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = DBPage.ID) and not WizardIsTaskSelected('curated');
end;

procedure Fetch(const URL, Name, Hash: String);
begin
  DownloadPage.Clear;
  DownloadPage.Add(URL, Name, Hash);
  DownloadPage.Show;
  try
    DownloadPage.Download;
  finally
    DownloadPage.Hide;
  end;
end;

procedure EnsureConda();
var Root: String;
begin
  Root := ExpandConstant('{app}\miniforge3');
  CondaExe := Root + '\Scripts\conda.exe';
  if FileExists(CondaExe) then Exit;
  CondaExe := ExistingConda();
  if CondaExe <> '' then Exit;
  if DirExists(Root) then RaiseException('Incomplete Miniforge directory: ' + Root);
  Fetch(MFURL, 'miniforge-bootstrap.exe', MFSHA);
  { NSIS /D must be last and unquoted, even when the path contains spaces. }
  SetStage('Installing Miniforge...');
  RunChecked(ExpandConstant('{tmp}\miniforge-bootstrap.exe'),
    '/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=' + Root, ExpandConstant('{tmp}'));
  CondaExe := Root + '\Scripts\conda.exe';
  if not FileExists(CondaExe) then RaiseException('Miniforge did not create conda.exe');
end;

procedure InstallEnvironment();
var A, Channels, Packages: String;
    Legacy: TFindRec;
begin
  Channels := ' --override-channels --strict-channel-priority -c conda-forge -c bioconda -c franciscolobo';
  Packages := ' r-localignr-windows={#AppVersion} r-jsonlite r-yaml r-openxlsx vc14_runtime ucrt';
  if FindFirst(EnvPrefix + '\conda-meta\r-localignr-*.json', Legacy) then begin
    try
      repeat
        if Pos('r-localignr-windows-', Legacy.Name) <> 1 then
          RaiseException('This is an older Conda-managed LocAlignR environment. Use a fresh installation directory.');
      until not FindNext(Legacy);
    finally
      FindClose(Legacy);
    end;
  end;
  if FindFirst(EnvPrefix + '\conda-meta\blast-*.json', Legacy) then begin
    FindClose(Legacy);
    RaiseException('Conda-managed BLAST detected. Use a fresh installation directory.');
  end;
  if FindFirst(EnvPrefix + '\conda-meta\diamond-*.json', Legacy) then begin
    FindClose(Legacy);
    RaiseException('Conda-managed DIAMOND detected. Use a fresh installation directory.');
  end;
  if FileExists(EnvPrefix + '\conda-meta\history') then A := 'install'
  else begin
    if DirExists(EnvPrefix) then RaiseException('Incomplete environment: ' + EnvPrefix);
    A := 'create';
  end;
  SetStage('Installing LocAlignR and R dependencies...');
  RunChecked(CondaExe, A + ' --prefix ' + Q(EnvPrefix) + ' --yes' + Channels + Packages, ExpandConstant('{app}'));
end;

procedure InstallEngines();
var TarExe, BlastDir, DiamondDir: String;
begin
  TarExe := ExpandConstant('{sys}\tar.exe');
  if not FileExists(TarExe) then RaiseException('Windows tar.exe is required.');
  SetStage('Downloading official BLAST+ 2.17.0 from NCBI...');
  Fetch(BLASTURL, 'blast-upstream.tar.gz', BLASTSHA);
  SetStage('Downloading official DIAMOND 2.2.8 from GitHub...');
  Fetch(DIAMONDURL, 'diamond-upstream.zip', DIAMONDSHA);
  BlastDir := ExpandConstant('{tmp}\blast-upstream');
  DiamondDir := ExpandConstant('{tmp}\diamond-upstream');
  if DirExists(BlastDir) then
    if not DelTree(BlastDir, True, True, True) then RaiseException('Cannot clear temporary BLAST extraction directory.');
  if DirExists(DiamondDir) then
    if not DelTree(DiamondDir, True, True, True) then RaiseException('Cannot clear temporary DIAMOND extraction directory.');
  if not ForceDirectories(BlastDir) or not ForceDirectories(DiamondDir) then
    RaiseException('Cannot create engine extraction directories.');
  SetStage('Extracting checksum-verified alignment engines...');
  RunChecked(TarExe, '-xf ' + Q(ExpandConstant('{tmp}\blast-upstream.tar.gz')) + ' -C ' + Q(BlastDir), BlastDir);
  RunChecked(TarExe, '-xf ' + Q(ExpandConstant('{tmp}\diamond-upstream.zip')) + ' -C ' + Q(DiamondDir), DiamondDir);
  SetStage('Installing official alignment executables...');
  RunEnv('Rscript --vanilla ' + Q(ExpandConstant('{tmp}\install_engines.R')) + ' ' + Q(BlastDir) + ' ' + Q(DiamondDir));
  SetStage('Validating the LocAlignR environment and alignment engines...');
  RunEnv('Rscript --vanilla ' + Q(ExpandConstant('{tmp}\check_install.R')) + ' {#AppVersion}');
end;

procedure SaveLauncher();
var B, P: String;
begin
  P := CondaExe;
  StringChangeEx(P, '%', '%%', True);
  B := '@echo off' + #13#10 + 'setlocal DisableDelayedExpansion' + #13#10 +
    'title LocAlignR' + #13#10 + 'cd /d "%~dp0"' + #13#10 +
    Q(P) + ' run --prefix "%~dp0envs\localignr" --no-capture-output Rscript --vanilla "%~dp0launch.R"' + #13#10 +
    'if errorlevel 1 pause' + #13#10;
  if not SaveStringToFile(ExpandConstant('{app}\launch.cmd'), B, False) then RaiseException('Cannot write launcher');
  if not SaveStringToFile(ExpandConstant('{app}\conda-path.txt'), CondaExe, False) then RaiseException('Cannot save Conda location');
end;

procedure InstallOneDatabase(const L: TArrayOfString; I: Integer);
var Parent, Dest, Archive, Base, TarExe, Manifest, Helper: String;
begin
  Parent := RemoveBackslashUnlessRoot(ExpandFileName(DBPage.Values[0]));
  if Pos(Lowercase(AddBackslash(ExpandConstant('{app}'))), Lowercase(AddBackslash(Parent))) = 1 then
    RaiseException('Choose a database directory outside the application installation folder.');
  if not ForceDirectories(Parent) then RaiseException('Cannot create database parent: ' + Parent);
  { Versioned destination; never overwrite an existing directory. }
  Dest := AddBackslash(Parent) + L[I] + '-' + L[I+2];
  if DirExists(Dest) then RaiseException('Database directory already exists: ' + Dest + '. Choose another parent or inspect the existing database first.');
  TarExe := ExpandConstant('{sys}\tar.exe');
  if not FileExists(TarExe) then RaiseException('Windows tar.exe is required for database installation.');
  Fetch(L[I+4], L[I+3], L[I+5]);
  Archive := ExpandConstant('{tmp}\') + L[I+3];
  if not ForceDirectories(Dest) then RaiseException('Cannot create ' + Dest);
  { Match the macOS extraction of the checksum-verified trusted archive. }
  SetStage('Extracting ' + L[I+1] + ' sequences and metadata...');
  RunChecked(TarExe, '-xzf ' + Q(Archive) + ' -C ' + Q(Dest), Dest);
  if not FileExists(AddBackslash(Dest) + L[I+6]) or not FileExists(AddBackslash(Dest) + L[I+7]) then
    RaiseException('Expected FASTA or metadata is missing');
  Base := AddBackslash(Dest) + L[I+8];
  SetStage('Formatting ' + L[I+1] + ' for BLAST...');
  RunEnv('makeblastdb -in ' + Q(AddBackslash(Dest) + L[I+6]) + ' -dbtype prot -out ' + Q(Base) + ' -parse_seqids');
  SetStage('Formatting ' + L[I+1] + ' for DIAMOND...');
  RunEnv('diamond makedb --in ' + Q(AddBackslash(Dest) + L[I+6]) + ' --db ' + Q(Base));
  SetStage('Validating both database indexes...');
  RunEnv('blastdbcmd -db ' + Q(Base) + ' -info');
  RunEnv('diamond dbinfo --db ' + Q(Base + '.dmnd'));
  Manifest := ExpandConstant('{tmp}\db_manifest.json');
  Helper := ExpandConstant('{tmp}\manifest_registry.R');
  SetStage('Registering the database and metadata in LocAlignR...');
  RunEnv('Rscript --vanilla ' + Q(Helper) + ' register ' + Q(Manifest) + ' ' + Q(L[I]) + ' ' + Q(Dest));
  DeleteFile(Archive);
  Log('Registered curated database: ' + Dest);
end;

procedure InstallDatabases();
var L: TArrayOfString; I: Integer; Plan: String;
begin
  SetStage('Reading the curated database manifest...');
  Plan := ExpandConstant('{tmp}\db-plan.txt');
  RunEnv('Rscript --vanilla ' + Q(ExpandConstant('{tmp}\manifest_registry.R')) + ' plan ' + Q(ExpandConstant('{tmp}\db_manifest.json')) + ' ' + Q(Plan));
  if not LoadStringsFromFile(Plan,L) then RaiseException('Cannot read database manifest plan');
  if (GetArrayLength(L)=0) or ((GetArrayLength(L) mod 10)<>0) then RaiseException('Invalid database manifest plan');
  I := 0;
  while I < GetArrayLength(L) do begin
    if WizardSilent or (MsgBox('Install ' + L[I+1] + ' (' + L[I+2] + ')?' + #13#10 + 'Includes sequences, metadata and both indexes.', mbConfirmation, MB_YESNO)=IDYES) then
      InstallOneDatabase(L,I);
    I := I + 10;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := ''; NeedsRestart := False;
  if Prepared then Exit;
  try
    if not ForceDirectories(ExpandConstant('{app}')) then RaiseException('Cannot create application directory');
    EnvPrefix := ExpandConstant('{app}\envs\localignr');
    ExtractTemporaryFile('db_manifest.json');
    ExtractTemporaryFile('manifest_registry.R');
    ExtractTemporaryFile('check_install.R');
    ExtractTemporaryFile('install_engines.R');
    SetStage('Checking for Conda or Miniforge...');
    EnsureConda();
    InstallEnvironment();
    InstallEngines();
    SetStage('Creating the LocAlignR launcher...');
    SaveLauncher();
    if WizardIsTaskSelected('curated') then begin
      try
        InstallDatabases();
      except
        Log('Optional database installation failed: ' + GetExceptionMessage);
        if not WizardSilent then MsgBox('LocAlignR is installed, but optional database setup did not complete.' + #13#10 + GetExceptionMessage + #13#10 + 'Any partial database files are retained for inspection.', mbInformation, MB_OK);
      end;
    end;
    Prepared := True;
  except
    Result := GetExceptionMessage;
    Log(Result);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var A: AnsiString; P: String;
begin
  if CurUninstallStep = usUninstall then begin
    P := ExpandConstant('{app}\envs\localignr');
    if FileExists(P + '\conda-meta\history') then begin
      try
        if not LoadStringFromFile(ExpandConstant('{app}\conda-path.txt'), A) then RaiseException('Saved Conda path missing');
        CondaExe := String(A);
        if not FileExists(CondaExe) then RaiseException('Saved Conda executable missing');
        RunChecked(CondaExe, 'env remove --prefix ' + Q(P) + ' --yes', ExpandConstant('{app}'));
      except
        Log('Environment removal failed: ' + GetExceptionMessage);
        if not UninstallSilent then MsgBox('Environment retained at ' + P + #13#10 + GetExceptionMessage, mbInformation, MB_OK);
      end;
    end;
    { Never remove user database directories or registry. Private Miniforge is retained in this development revision. }
  end;
end;
