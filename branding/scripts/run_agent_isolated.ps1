<#
.SYNOPSIS
    Starts one Herdr agent in a new, never-reused Windows profile directory.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentKey,

    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentCommand,

    [Parameter(Position = 2, ValueFromRemainingArguments)]
    [string[]]$AgentArguments = @()
)

$ErrorActionPreference = "Stop"

# Resolve the executable before changing HOME/USERPROFILE, since some agents are
# installed inside the real user profile (for example ~/.gemini/bin/agy.exe).
$commandInfo = Get-Command -Name $AgentCommand -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
$resolvedCommand = if ($commandInfo.Path) { $commandInfo.Path } else { $commandInfo.Source }

$hostProfile = $env:USERPROFILE
$hostHome = $env:HOME
$hostAppData = $env:APPDATA
$hostLocalAppData = $env:LOCALAPPDATA
$environmentRoot = Join-Path $env:LOCALAPPDATA "Nauagency\Herdr\agent-environments"
$safeAgentKey = $AgentKey -replace '[^A-Za-z0-9._-]', '-'
$environmentId = "{0}-{1}-{2}" -f $safeAgentKey, (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$profileDir = Join-Path $environmentRoot $environmentId
$roamingDir = Join-Path $profileDir "AppData\Roaming"
$localDir = Join-Path $profileDir "AppData\Local"

foreach ($dir in @($profileDir, $roamingDir, $localDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$metadata = [ordered]@{
    id = $environmentId
    agent = $AgentKey
    createdAt = (Get-Date).ToString("o")
    hostProfile = $hostProfile
    command = $resolvedCommand
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileDir "environment.json") -Encoding UTF8

$env:NAUAGENCY_AGENT_ENVIRONMENT_ID = $environmentId
$env:NAUAGENCY_HOST_PROFILE = $hostProfile
$env:USERPROFILE = $profileDir
$env:HOME = $profileDir
$env:APPDATA = $roamingDir
$env:LOCALAPPDATA = $localDir

Write-Host "New isolated agent environment: $environmentId" -ForegroundColor DarkGray
Write-Host "Space is unchanged; this tab has its own profile and session data." -ForegroundColor DarkGray

$agentExitCode = 1
try {
    & $resolvedCommand @AgentArguments
    $agentExitCode = $LASTEXITCODE
} finally {
    $env:USERPROFILE = $hostProfile
    $env:HOME = $hostHome
    $env:APPDATA = $hostAppData
    $env:LOCALAPPDATA = $hostLocalAppData
    Remove-Item Env:NAUAGENCY_AGENT_ENVIRONMENT_ID -ErrorAction SilentlyContinue
    Remove-Item Env:NAUAGENCY_HOST_PROFILE -ErrorAction SilentlyContinue
}

exit $agentExitCode
