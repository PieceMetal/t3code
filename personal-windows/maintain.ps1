[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Build', 'Check', 'Verify')][string]$Task,
    [string]$Version,
    [string]$BaseRef,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Background maintenance must run as a standard user.'
}
$repo = Split-Path -Parent $PSScriptRoot
$desk = Join-Path $env:USERPROFILE '.local-agent-desk'
$tool = Join-Path $desk 'tooling'
$node = Join-Path $tool 'node.exe'
$vp = Join-Path $repo 'node_modules/.bin/vp.cmd'
$env:PATH = $tool + ';' + (Join-Path $repo 'node_modules/.bin') + ';' + $env:PATH
$env:PNPM_HOME = Join-Path $tool 'pnpm-home'
Set-Location -LiteralPath $repo

function Invoke-Step([string]$Directory, [string]$Program, [string[]]$Arguments) {
    Push-Location -LiteralPath $Directory
    try {
        & $Program @Arguments
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally { Pop-Location }
}

if ($Task -eq 'Verify') {
    $exe = Join-Path $desk 'desktop-app/T3 Agent Desk.exe'
    if ((Get-Item -LiteralPath $exe).VersionInfo.ProductName -ne 'T3 Agent Desk') {
        throw 'Unexpected desktop executable'
    }
    $listener = Get-NetTCPConnection -LocalPort 48773 -State Listen
    if ($listener.LocalAddress -ne '127.0.0.1' -or (Get-Process -Id $listener.OwningProcess).Path -ine $exe) {
        throw 'The expected local desktop server is not running'
    }
    $manifest = Invoke-RestMethod 'http://127.0.0.1:48773/manifest.webmanifest' -TimeoutSec 5
    if ($manifest.name -ne 'T3 Agent Desk') { throw 'Unexpected application name' }
    Write-Output 'Verified T3 Agent Desk and its local server.'
    exit 0
}

if (-not $OutputDirectory) { throw 'Specify an output directory for build or check files.' }
if ($Task -eq 'Build' -and -not $Version) { throw 'Specify a version for the private build.' }
$work = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
$env:TMPDIR = $work
$env:TEMP = $work
$env:TMP = $work
$env:CI = 'true'
if ($Task -eq 'Check') {
    $checkArgs = @('run', 'check:changed')
    if ($BaseRef) { $checkArgs += $BaseRef }
    Invoke-Step $repo $vp $checkArgs
    exit 0
}

$env:APP_VERSION = $Version
$env:T3CODE_DESKTOP_VERSION = $Version
$env:T3CODE_DESKTOP_REUSE_RESOURCE_MONITOR = 'true'
$env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'
Invoke-Step "$repo/apps/web" $vp @('build')
Invoke-Step "$repo/apps/desktop" $vp @('pack')
Invoke-Step "$repo/apps/server" $node @('scripts/cli.ts', 'build')
Invoke-Step "$repo/apps/server" $node @('scripts/cli.ts', 'build-exe')
Invoke-Step $repo $node @('scripts/build-cli-archive.ts', '--platform', 'win', '--arch', 'x64',
    '--version', $Version, '--output-dir', "$work/archives", '--resource-monitor-dir', "$desk/app/resource-monitor")
Invoke-Step $repo $node @('scripts/build-desktop-artifact.ts', '--platform', 'win', '--target', 'dir',
    '--arch', 'x64', '--build-version', $Version, '--output-dir', "$work/desktop", '--skip-build')
