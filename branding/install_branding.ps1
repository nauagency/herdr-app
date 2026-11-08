<#
.SYNOPSIS
    Applies the Nauagency layout and mods on top of an official Herdr install.
.DESCRIPTION
    This script only changes Herdr configuration under ~/.config/herdr-app.
    It does not install a replacement executable, create account profiles, or
    create custom Windows shortcuts.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$sourceRoot = Join-Path $scriptDir "herdr-app"
$sourceLayouts = Join-Path $sourceRoot "layouts"
$sourceMods = Join-Path $sourceRoot "mods"
$sourceScripts = Join-Path $scriptDir "scripts"
$configDir = Join-Path $env:USERPROFILE ".config\herdr-app"
$layoutsDir = Join-Path $configDir "layouts"
$modsDir = Join-Path $configDir "mods"
$backupsDir = Join-Path $configDir "backups"

$requiredFiles = @(
    (Join-Path $sourceLayouts "nauagency.json"),
    (Join-Path $sourceLayouts "nauagency.svg")
)

foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required branding file is missing: $requiredFile"
    }
}

foreach ($dir in @($configDir, $layoutsDir, $modsDir, $backupsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $backupsDir "branding_$timestamp"
$backupCreated = $false

function Backup-ConfigItem {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not $script:backupCreated) {
        New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null
        $script:backupCreated = $true
    }

    $relativePath = $Path.Substring($script:configDir.Length).TrimStart('\', '/')
    $destination = Join-Path $script:backupDir $relativePath
    $destinationParent = Split-Path $destination -Parent
    if (-not (Test-Path -LiteralPath $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
}

Backup-ConfigItem -Path (Join-Path $layoutsDir "nauagency.json")
Backup-ConfigItem -Path (Join-Path $layoutsDir "nauagency.svg")
Backup-ConfigItem -Path (Join-Path $configDir "shared.json")

if (Test-Path -LiteralPath $sourceMods) {
    foreach ($sourceMod in Get-ChildItem -LiteralPath $sourceMods -Directory) {
        Backup-ConfigItem -Path (Join-Path $modsDir $sourceMod.Name)
    }
}

Copy-Item -LiteralPath (Join-Path $sourceLayouts "nauagency.json") -Destination (Join-Path $layoutsDir "nauagency.json") -Force
Copy-Item -LiteralPath (Join-Path $sourceLayouts "nauagency.svg") -Destination (Join-Path $layoutsDir "nauagency.svg") -Force

if (Test-Path -LiteralPath $sourceMods) {
    foreach ($sourceMod in Get-ChildItem -LiteralPath $sourceMods -Directory) {
        $destinationMod = Join-Path $modsDir $sourceMod.Name
        if (Test-Path -LiteralPath $destinationMod) {
            Remove-Item -LiteralPath $destinationMod -Recurse -Force
        }
        Copy-Item -LiteralPath $sourceMod.FullName -Destination $destinationMod -Recurse -Force
    }
}

if (Test-Path -LiteralPath $sourceScripts) {
    foreach ($scriptName in @("run_agent_isolated.ps1")) {
        $sourceScript = Join-Path $sourceScripts $scriptName
        if (Test-Path -LiteralPath $sourceScript) {
            Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $configDir $scriptName) -Force
        }
    }
}

$sharedJsonPath = Join-Path $configDir "shared.json"
$shared = $null
Add-Type -AssemblyName System.Web.Extensions
$jsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonSerializer.MaxJsonLength = [int]::MaxValue
if (Test-Path -LiteralPath $sharedJsonPath) {
    try {
        $raw = Get-Content -LiteralPath $sharedJsonPath -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            # Herdr stores the local machine under an empty-string JSON key.
            # Windows PowerShell's ConvertFrom-Json rejects that valid key, while
            # JavaScriptSerializer preserves it and the rest of the settings.
            $shared = $jsonSerializer.DeserializeObject($raw)
        }
    } catch {
        Write-Warning "Existing shared.json is invalid; a clean file will be written. $_"
    }
}

if ($null -eq $shared) {
    $shared = New-Object 'System.Collections.Generic.Dictionary[string,object]'
}

$shared["layout"] = "nauagency"
$shared["frame.welcomed"] = "finished"

$sharedJson = $jsonSerializer.Serialize($shared)
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($sharedJsonPath, $sharedJson, $utf8WithoutBom)

$herdrExe = Join-Path $env:LOCALAPPDATA "Programs\herdr-app\herdr-app.exe"
if (Test-Path -LiteralPath $herdrExe) {
    foreach ($sourceMod in Get-ChildItem -LiteralPath $sourceMods -Directory -ErrorAction SilentlyContinue) {
        $destinationMod = Join-Path $modsDir $sourceMod.Name
        $quotedDestination = '"' + $destinationMod + '"'
        $checkProcess = Start-Process -FilePath $herdrExe -ArgumentList @("check", $quotedDestination) -NoNewWindow -Wait -PassThru
        if ($checkProcess.ExitCode -ne 0) {
            throw "Herdr rejected mod: $($sourceMod.Name)"
        }
    }
}

Write-Host "Nauagency layout and mods were installed into: $configDir" -ForegroundColor Green
if ($backupCreated) {
    Write-Host "Previous branding files were backed up to: $backupDir" -ForegroundColor DarkGray
}
Write-Host "Restart Herdr to load the updated configuration." -ForegroundColor Cyan
