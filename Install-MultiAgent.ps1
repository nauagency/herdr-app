[CmdletBinding()]
param(
    [switch]$SkipBranding
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$officialInstallerUrl = "https://releases.herdr.dev/app/install.ps1"
$herdrExe = Join-Path $env:LOCALAPPDATA "Programs\herdr-app\herdr-app.exe"
$brandingScript = Join-Path $PSScriptRoot "branding\install_branding.ps1"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       HERDR OFFICIAL + NAUAGENCY CONFIG FOR WINDOWS      " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/2] Installing or updating the official Herdr app..." -ForegroundColor Cyan
$officialInstaller = Invoke-RestMethod -Uri $officialInstallerUrl
Invoke-Expression $officialInstaller

if (-not (Test-Path -LiteralPath $herdrExe)) {
    throw "Official Herdr executable was not found after installation: $herdrExe"
}

$version = (Get-Item -LiteralPath $herdrExe).VersionInfo.ProductVersion
Write-Host "  -> Official Herdr $version is installed." -ForegroundColor Green

if ($SkipBranding) {
    Write-Host "[2/2] Branding skipped by request." -ForegroundColor DarkGray
} else {
    if (-not (Test-Path -LiteralPath $brandingScript)) {
        throw "Branding script is missing: $brandingScript"
    }

    Write-Host "[2/2] Applying Nauagency layout and mods..." -ForegroundColor Cyan
    & $brandingScript
}

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "- Uses the official Herdr Windows build." -ForegroundColor White
Write-Host "- Does not create acc1-acc6 or agy-1-agy-6 launchers." -ForegroundColor White
Write-Host "- Does not create a Multi Agent Herdr desktop or Start Menu shortcut." -ForegroundColor White
Write-Host "- Open the app using the official Herdr Start Menu entry or herdr-app." -ForegroundColor White
