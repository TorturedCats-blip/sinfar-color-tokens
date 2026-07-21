param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'

function Read-NormalizedText([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "Required source file was not found: $Path"
    }
    return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
}

function Replace-RequiredText(
    [string]$Content,
    [string]$OldText,
    [string]$NewText,
    [string]$Description
) {
    $oldNormalized = $OldText.Replace("`r`n", "`n")
    $newNormalized = $NewText.Replace("`r`n", "`n")
    if (-not $Content.Contains($oldNormalized)) {
        throw "Expected source block was not found for: $Description"
    }
    return $Content.Replace($oldNormalized, $newNormalized)
}

$programPath = Join-Path $SourceRoot 'src/SinfarCrashAtlas.App/Program.cs'
$program = Read-NormalizedText $programPath

$oldCaptureBlock = @'
            capture.CrashAtlasElevated = IsRunningAsAdministrator();
            capture.DeepResourceTraceRequested = deepTraceRequested;
            capture.DeepResourceTraceEnabled = traceScope?.Enabled == true;
            capture.WerMinidumpRequested = minidumpRequested;
            capture.WerMinidumpEnabled = dumpScope?.Enabled == true;
            capture.WerDumpFolder = dumpScope?.DumpFolder ?? string.Empty;
            capture.ResourceTraceConfigurationRestored = traceScope?.Restore() ?? !deepTraceRequested;
            capture.WerConfigurationRestored = dumpScope?.Restore() ?? !minidumpRequested;
            _pendingWerRecovery = OperatingSystem.IsWindows() && WerLocalDumpScope.HasPendingRecovery(DataRoot);
'@

$newCaptureBlock = @'
            capture.CrashAtlasElevated = IsRunningAsAdministrator();
            capture.DeepResourceTraceRequested = deepTraceRequested;
            capture.DeepResourceTraceEnabled = traceScope?.Enabled == true;
            capture.WerMinidumpRequested = minidumpRequested;
            capture.ResourceTraceConfigurationRestored = traceScope?.Restore() ?? !deepTraceRequested;

            if (OperatingSystem.IsWindows())
            {
                capture.WerMinidumpEnabled = dumpScope?.Enabled == true;
                capture.WerDumpFolder = dumpScope?.DumpFolder ?? string.Empty;
                capture.WerConfigurationRestored = dumpScope?.Restore() ?? !minidumpRequested;
                _pendingWerRecovery = WerLocalDumpScope.HasPendingRecovery(DataRoot);
            }
            else
            {
                capture.WerMinidumpEnabled = false;
                capture.WerDumpFolder = string.Empty;
                capture.WerConfigurationRestored = !minidumpRequested;
                _pendingWerRecovery = false;
            }
'@

$program = Replace-RequiredText $program $oldCaptureBlock $newCaptureBlock 'Windows WER capture guard'

$oldAdministratorMethod = @'
    [SupportedOSPlatform("windows")]
    private static bool IsRunningAsAdministrator()
    {
        try
'@

$newAdministratorMethod = @'
    private static bool IsRunningAsAdministrator()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
'@

$program = Replace-RequiredText $program $oldAdministratorMethod $newAdministratorMethod 'administrator platform guard'
[IO.File]::WriteAllText($programPath, $program, [Text.UTF8Encoding]::new($false))

$launcherPath = Join-Path $SourceRoot 'src/SinfarCrashAtlas.App/SinfarLauncherDiscovery.cs'
$launcher = Read-NormalizedText $launcherPath
$launcher = Replace-RequiredText $launcher 'isEe ? "SinfarXEE / NWN:EE 81.8193.16" : "SinfarX / NWN Diamond 1.69"' 'isEe ? "SinfarXEE / Neverwinter Nights: Enhanced Edition 81.8193.16" : "SinfarX / NWN Diamond 1.69"' 'Enhanced Edition launcher profile name'
[IO.File]::WriteAllText($launcherPath, $launcher, [Text.UTF8Encoding]::new($false))

$repositoryPath = Join-Path $SourceRoot 'src/SinfarCrashAtlas.Reporting/SqliteReportRepository.cs'
$repository = Read-NormalizedText $repositoryPath
$oldConnectionOptions = @'
            DataSource = fullPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared
'@
$newConnectionOptions = @'
            DataSource = fullPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
            Pooling = false
'@
$repository = Replace-RequiredText $repository $oldConnectionOptions $newConnectionOptions 'SQLite connection pool lifetime'
[IO.File]::WriteAllText($repositoryPath, $repository, [Text.UTF8Encoding]::new($false))

Write-Host 'Applied Crash Atlas v0.3.0 compile and test fixes.'
