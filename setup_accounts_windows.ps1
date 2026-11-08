<#
.SYNOPSIS
    Compatibility entry point for the Windows installer.
.DESCRIPTION
    Older versions created six local Antigravity profiles. The current setup
    intentionally keeps account management inside official Herdr and delegates
    only to Install-MultiAgent.ps1.
#>

[CmdletBinding()]
param(
    [switch]$SkipBranding
)

$ErrorActionPreference = "Stop"
$installer = Join-Path $PSScriptRoot "Install-MultiAgent.ps1"

if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer not found: $installer"
}

& $installer -SkipBranding:$SkipBranding
