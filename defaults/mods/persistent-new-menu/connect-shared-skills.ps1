[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("codex", "claude", "antigravity")][string]$Provider,
    [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$ConfigRoot,
    [Parameter(Position = 2)][string]$SharedRoot = "D:\Skill-Agent\shared"
)

$ErrorActionPreference = "Stop"
$shared = [IO.Path]::GetFullPath($SharedRoot)
if (-not (Test-Path -LiteralPath $shared -PathType Container)) { exit 0 }

$config = [IO.Path]::GetFullPath($ConfigRoot)
$skillsDir = switch ($Provider) {
    "antigravity" { Join-Path $config "config\skills" }
    default { Join-Path $config "skills" }
}
New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null

$ruleFile = switch ($Provider) {
    "codex" { Join-Path $config "AGENTS.md" }
    "claude" { Join-Path $config "CLAUDE.md" }
    "antigravity" { Join-Path (Join-Path $config "config") "GEMINI.md" }
}
$ruleParent = Split-Path -Parent $ruleFile
New-Item -ItemType Directory -Path $ruleParent -Force | Out-Null
$marker = "HERDR_SHARED_SKILLS_RULE_V1"
$existingRule = if (Test-Path -LiteralPath $ruleFile) { Get-Content -LiteralPath $ruleFile -Raw -ErrorAction SilentlyContinue } else { "" }
if ($existingRule -notmatch $marker) {
    $sharedRule = @"

<!-- $marker -->
## Shared skill storage

All user-created or user-edited skills must be saved under `D:\Skill-Agent\shared\<skill-name>\` with `SKILL.md` as the entry file. Do not create a custom skill only inside this account's local config folder. Platform-managed built-in skills and plugin caches remain in their platform directories.

After creating, renaming, or deleting a shared skill, run:

`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "D:\Skill-Agent\sync-all.ps1"`

This rule applies to direct sessions and Multi Agent Herdr profiles. Existing explicit user instructions take priority.
<!-- /$marker -->
"@
    Set-Content -LiteralPath $ruleFile -Value ($existingRule.TrimEnd() + $sharedRule) -Encoding UTF8
}

foreach ($skill in Get-ChildItem -LiteralPath $shared -Directory -Force -ErrorAction SilentlyContinue) {
    $skillFile = Join-Path $skill.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
    $destination = Join-Path $skillsDir $skill.Name
    if (Test-Path -LiteralPath $destination) { continue }
    try { New-Item -ItemType Junction -Path $destination -Target $skill.FullName -ErrorAction Stop | Out-Null }
    catch { Write-Warning "Cannot connect shared skill '$($skill.Name)' for ${Provider}: $($_.Exception.Message)" }
}

[pscustomobject]@{
    provider = $Provider
    configRoot = $config
    skillsDirectory = $skillsDir
    sharedRoot = $shared
    connected = @(Get-ChildItem -LiteralPath $skillsDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType -eq "Junction" }).Count
} | ConvertTo-Json -Compress
