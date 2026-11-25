$ErrorActionPreference = 'Stop'
$forward = @($args)
$root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local-agent-desk'
$app = Join-Path $root 'app'
$launcher = Join-Path $app 'Start-LocalAgentDesk.ps1'
if ($forward.Count -eq 0 -or ($forward.Count -eq 1 -and $forward[0] -ieq 'start')) {
    $desktop = Join-Path $root 'desktop-app/T3 Agent Desk.exe'
    $start = [Diagnostics.ProcessStartInfo]::new($desktop)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = [IO.Path]::GetDirectoryName($desktop)
    [void][Diagnostics.Process]::Start($start)
    exit 0
}
if ($forward.Count -eq 1 -and $forward[0] -ieq 'serve') {
    & $launcher -Headless
    exit $LASTEXITCODE
}
foreach ($name in @('ELECTRON_RUN_AS_NODE', 'T3CODE_DESKTOP_CLI_LAUNCHER', 'NODE_OPTIONS', 'NODE_PATH',
        'NODE_COMPILE_CACHE', 'VITE_DEV_SERVER_URL', 'T3CODE_DEV_AUTH_TOKEN', 'T3CODE_DEV_ALLOWED_ORIGINS',
        'T3CODE_BOOTSTRAP_FD')) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$env:T3CODE_HOME = Join-Path $root 'data'
$env:T3CODE_CLI_PATH = Join-Path $PSScriptRoot 't3.cmd'
$env:T3CODE_TELEMETRY_ENABLED = 'false'
$env:T3CODE_OTEL_SDK_DISABLED = 'true'
$env:NODE_ENV = 'production'
& (Join-Path $app 't3.exe') @forward
exit $LASTEXITCODE
