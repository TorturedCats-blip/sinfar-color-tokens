param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'
$programPath = Join-Path $SourceRoot 'src/SinfarCrashAtlas.App/Program.cs'
if (-not (Test-Path $programPath)) {
    throw "Program.cs was not found at $programPath"
}

$content = [IO.File]::ReadAllText($programPath).Replace("`r`n", "`n")

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
$oldCaptureBlock = $oldCaptureBlock.Replace("`r`n", "`n")

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
$newCaptureBlock = $newCaptureBlock.Replace("`r`n", "`n")

if (-not $content.Contains($oldCaptureBlock)) {
    throw 'Expected WER capture block was not found; refusing an unsafe patch.'
}
$content = $content.Replace($oldCaptureBlock, $newCaptureBlock)

$oldAdministratorMethod = @'
    [SupportedOSPlatform("windows")]
    private static bool IsRunningAsAdministrator()
    {
        try
'@
$oldAdministratorMethod = $oldAdministratorMethod.Replace("`r`n", "`n")

$newAdministratorMethod = @'
    private static bool IsRunningAsAdministrator()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
'@
$newAdministratorMethod = $newAdministratorMethod.Replace("`r`n", "`n")

if (-not $content.Contains($oldAdministratorMethod)) {
    throw 'Expected administrator helper declaration was not found; refusing an unsafe patch.'
}
$content = $content.Replace($oldAdministratorMethod, $newAdministratorMethod)

[IO.File]::WriteAllText($programPath, $content, [Text.UTF8Encoding]::new($false))
Write-Host "Applied Crash Atlas v0.3.0 platform-analysis fixes to $programPath"
