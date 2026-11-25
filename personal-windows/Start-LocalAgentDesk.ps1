[CmdletBinding()]
param([switch]$Headless, [switch]$Prepare, [switch]$Reduced, [switch]$Desktop, [switch]$VerifyDesktop)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$powershell = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
if ($VerifyDesktop -and -not $Desktop) { throw 'Desktop verification requires desktop mode.' }
if (-not ($Prepare -or $Reduced -or $VerifyDesktop)) {
    if ($Desktop) {
        & $powershell -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File $PSCommandPath -Prepare -Desktop
    } elseif ($Headless) {
        & $powershell -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File $PSCommandPath -Prepare -Headless
    } else {
        & $powershell -NoLogo -NoProfile -File $PSCommandPath -Prepare
    }
    exit $LASTEXITCODE
}

$root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local-agent-desk'
$data = Join-Path $root 'data'
$userData = Join-Path $data 'userdata'
$secrets = Join-Path $userData 'secrets'
$scratch = Join-Path $root 'temp'
$runtime = if ($Desktop) {
    Join-Path ([IO.Directory]::GetParent($PSScriptRoot).FullName) 'T3 Agent Desk.exe'
} else {
    Join-Path $PSScriptRoot 't3.exe'
}
$trusted = @($identity.User.Value, 'S-1-5-18', 'S-1-5-32-544')

function Assert-PrivateItem([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unexpected link at $Path" }
    $acl = $item.GetAccessControl()
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $grants = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
        Where-Object { $_.AccessControlType -eq 'Allow' })
    if ($owner -notin $trusted -or $grants.Count -eq 0 -or
        @($grants | Where-Object { $_.IdentityReference.Value -notin $trusted }).Count -gt 0) {
        throw "T3 Agent Desk requires a private Windows access list at $Path"
    }
}

if (-not (Test-Path -LiteralPath $root)) {
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    foreach ($sid in $trusted) {
        $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid), 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    [void][IO.Directory]::CreateDirectory($root, $security)
}
Assert-PrivateItem $root
Assert-PrivateItem $PSScriptRoot
Assert-PrivateItem $runtime
if ($Desktop) {
    Assert-PrivateItem ([IO.Path]::GetDirectoryName($runtime))
    Assert-PrivateItem (Join-Path $PSScriptRoot 'app.asar')
    Assert-PrivateItem (Join-Path $PSScriptRoot 'server.asar')
    $desktopProfile = Join-Path $root 'desktop'
    if (-not (Test-Path -LiteralPath $desktopProfile)) { [void][IO.Directory]::CreateDirectory($desktopProfile) }
    Assert-PrivateItem $desktopProfile
}
foreach ($path in @($data, $userData, $secrets, $scratch)) {
    if (-not (Test-Path -LiteralPath $path)) { [void][IO.Directory]::CreateDirectory($path) }
    Assert-PrivateItem $path
}
Get-ChildItem -Force -LiteralPath $secrets | ForEach-Object { Assert-PrivateItem $_.FullName }
Get-ChildItem -Force -LiteralPath $userData -Filter 'statev2.sqlite*' |
    ForEach-Object { Assert-PrivateItem $_.FullName }

foreach ($name in @('NODE_OPTIONS', 'NODE_PATH', 'NODE_COMPILE_CACHE', 'VITE_DEV_SERVER_URL',
        'T3CODE_DEV_AUTH_TOKEN', 'T3CODE_DEV_ALLOWED_ORIGINS', 'T3CODE_BOOTSTRAP_FD',
        'ELECTRON_RUN_AS_NODE', 'ELECTRON_NO_SANDBOX', 'ELECTRON_EXTRA_LAUNCH_ARGS')) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$env:NODE_ENV = 'production'
$env:T3CODE_HOME = $data
$env:TEMP = $scratch
$env:TMP = $scratch
$env:T3CODE_TELEMETRY_ENABLED = 'false'
$env:T3CODE_OTEL_SDK_DISABLED = 'true'
$env:T3CODE_TAILSCALE_SERVE = 'false'
$env:T3CODE_AUTO_BOOTSTRAP_PROJECT_FROM_CWD = 'false'
$env:T3CODE_NO_BROWSER = $Headless.IsPresent.ToString().ToLowerInvariant()

$integritySource = Join-Path $PSScriptRoot 'LocalDeskIntegrity.cs'
Assert-PrivateItem $integritySource
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
Add-Type -Path $integritySource
if ($Prepare) {
    [LocalAgentDesk.ProcessIntegrity]::LimitOwnProcess()
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $window = if ($Headless -or $Desktop) { '-NonInteractive -WindowStyle Hidden ' } else { '' }
        $command = '"{0}" -NoLogo -NoProfile {1}-File "{2}" -Reduced' -f $powershell, $window, $PSCommandPath
        if ($Headless) { $command += ' -Headless' }
        if ($Desktop) { $command += ' -Desktop' }
        & (Join-Path ([Environment]::SystemDirectory) 'runas.exe') /trustlevel:0x20000 $command
        exit $LASTEXITCODE
    }
}
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    -not [LocalAgentDesk.ProcessIntegrity]::IsAtMostMedium()) {
    throw 'T3 Agent Desk needs standard-user rights and medium or lower Windows integrity.'
}
Set-Location -LiteralPath $data
if ($VerifyDesktop) { exit 0 }
if ($Desktop) {
    $env:LOCAL_AGENT_DESK_DESKTOP_READY = '1'
    $env:T3CODE_PORT = '48773'
    $env:T3CODE_NO_BROWSER = 'true'
    $si = [Diagnostics.ProcessStartInfo]::new($runtime)
    $si.UseShellExecute = $false
    $si.WorkingDirectory = $data
    [void][Diagnostics.Process]::Start($si)
    exit 0
}
& $runtime start --mode web --host 127.0.0.1 --port 48773 --base-dir $data
exit $LASTEXITCODE
