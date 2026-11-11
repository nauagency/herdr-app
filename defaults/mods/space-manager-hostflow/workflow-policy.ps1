[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("get", "set")][string]$Action,
    [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$SpaceId,
    [Parameter(Position = 2)][string]$LeadProfileId = "",
    [Parameter(Position = 3)][string]$ExecutorProfileIds = "",
    [Parameter(Position = 4)][string]$RepositoryPath = ""
)

$ErrorActionPreference = "Stop"
$root = if ($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT) {
    [IO.Path]::GetFullPath($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT)
} elseif ($env:NAUAGENCY_HOST_PROFILE) {
    Join-Path $env:NAUAGENCY_HOST_PROFILE "AppData\Local\Nauagency\Multi Agent Herdr\agent-environments"
} else {
    Join-Path $env:LOCALAPPDATA "Nauagency\Multi Agent Herdr\agent-environments"
}
$policyRoot = Join-Path $root "workflow-policies"
New-Item -ItemType Directory -Path $policyRoot -Force | Out-Null
$safeSpace = $SpaceId -replace '[^A-Za-z0-9._-]', '-'
$file = Join-Path $policyRoot "$safeSpace.json"

if ($Action -eq "get") {
    if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw }
    else { "{}" }
    exit 0
}

$executors = @($ExecutorProfileIds -split ',' | Where-Object { $_ -match '^[A-Za-z0-9._-]+$' } | Select-Object -Unique)
if ($LeadProfileId -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid Lead profile." }
if (-not $executors.Count) { throw "At least one executor profile is required." }
$policy = [ordered]@{
    schemaVersion = 2
    spaceId = $SpaceId
    enabled = $true
    leadProfileId = $LeadProfileId
    executorProfileIds = $executors
    repositoryPath = $RepositoryPath
    defaults = [ordered]@{ leadEffort = "medium"; executorModel = "gemini-3.8-flash"; executorEffort = "high" }
    contextProfiles = [ordered]@{ host = "full"; lead = "full"; executor = "lean" }
    execution = [ordered]@{
        mode = "local-only"
        allowed = @("local-process", "local-worktree", "local-file", "localhost-preview")
    }
    limits = [ordered]@{ maxReworkRounds = 3; sameErrorLimit = 2; maxExecutorBackups = 2; autoResumeLimit = 1; minQuotaPercent = 10 }
    approvals = @("merge", "deploy", "delete-data", "migration", "external-send", "scope-expansion")
    forbiddenPaths = @(".env", ".env.*", "**/.env", "**/.env.*", "**/*secret*", "**/*credential*", ".git/**")
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
}
$policy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
$policy | ConvertTo-Json -Compress -Depth 8
