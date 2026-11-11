[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$helper = Join-Path (Split-Path -Parent $PSScriptRoot) "defaults\mods\space-manager-hostflow\space-jobs.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("multi-agent-herdr-control-plane-{0}" -f [guid]::NewGuid().ToString("N"))
$spaceId = "control-plane-test"
$planPath = Join-Path $testRoot "plan.json"
$previousRoot = $env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT

function Invoke-ControlPlane([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments) {
    $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helper @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Control-plane command failed: $($Arguments -join ' ')" }
    return ($raw | Out-String).Trim()
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT = $testRoot
    @{
        idempotencyKey = "control-plane-test-v1"
        goal = "Verify deterministic task dependencies"
        tasks = @(
            @{ key = "build"; title = "Build"; description = "Build the change"; dependsOn = @(); routeMode = "lead-first"; maxAttempts = 2; timeoutMinutes = 30; requiresUserApproval = $false }
            @{ key = "review"; title = "Review"; description = "Review the build"; dependsOn = @("build"); routeMode = "lead-first"; maxAttempts = 1; timeoutMinutes = 10; requiresUserApproval = $true }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

    $created = (Invoke-ControlPlane plan-apply $spaceId $planPath) | ConvertFrom-Json
    Assert-True ($created.Count -eq 2) "Expected two tasks; got $($created.Count)."
    $build = $created | Where-Object taskKey -eq "build"
    $review = $created | Where-Object taskKey -eq "review"
    Assert-True ($build.status -eq "queued") "A root task must be queued."
    Assert-True ($review.status -eq "blocked") "A dependent task must be blocked."

    $replayed = (Invoke-ControlPlane plan-apply $spaceId $planPath) | ConvertFrom-Json
    Assert-True (($replayed.id | Sort-Object) -join "," -eq (($created.id | Sort-Object) -join ",")) "Plan application must be idempotent."

    $decision = (Invoke-ControlPlane request-decision $spaceId $review.id product-choice "task:$($review.id)" "Choose the review mode") | ConvertFrom-Json
    $resolved = (Invoke-ControlPlane decide $spaceId $review.id $decision.id approve "Test User") | ConvertFrom-Json
    Assert-True ($resolved.status -eq "blocked") "Resolving a decision must restore the task's previous state."

    $queued = (Invoke-ControlPlane enqueue $spaceId $review.id "Check the security boundary too") | ConvertFrom-Json
    Assert-True ($queued.status -eq "pending") "Steering must be queued durably."

    Invoke-ControlPlane update $spaceId $build.id failed "Synthetic failure" | Out-Null
    $jobs = (Invoke-ControlPlane list $spaceId) | ConvertFrom-Json
    $reviewAfterFailure = $jobs | Where-Object id -eq $review.id
    Assert-True ($reviewAfterFailure.status -eq "skipped") "A failed dependency must skip its blocked dependents."

    $events = (Invoke-ControlPlane events $spaceId 100) | ConvertFrom-Json
    Assert-True ($events.Count -ge 7) "Expected a durable event history."
    Assert-True (-not $events[0].previousHash) "The first event must start the hash chain."
    for ($index = 1; $index -lt $events.Count; $index++) {
        Assert-True ($events[$index].previousHash -eq $events[$index - 1].hash) "Event hash chain is broken at index $index."
        Assert-True ([string]$events[$index].hash -match '^[0-9a-f]{64}$') "Event hash is invalid at index $index."
    }

    Write-Host "Control-plane integration checks passed ($($events.Count) events)."
} finally {
    $env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT = $previousRoot
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
