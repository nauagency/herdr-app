[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("list", "events", "mailbox", "message", "complete-message", "plan-apply", "create", "dispatch", "route-dispatch", "auto-dispatch", "schedule", "route", "update", "request-decision", "decide", "enqueue", "deliver", "abandon", "reassign", "recover", "gate", "artifact", "checkpoint", "evidence", "review", "resolve-review")][string]$Action,
    [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$SpaceId,
    [Parameter(Position = 2, ValueFromRemainingArguments)][string[]]$Values = @()
)

$ErrorActionPreference = "Stop"
if ($env:HERDR_CORE_BIN -and (Test-Path -LiteralPath $env:HERDR_CORE_BIN -PathType Leaf)) {
    Set-Alias -Name hc -Value $env:HERDR_CORE_BIN -Scope Script
}
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = if ($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT) {
    [IO.Path]::GetFullPath($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT)
} elseif ($env:NAUAGENCY_HOST_PROFILE) {
    Join-Path $env:NAUAGENCY_HOST_PROFILE "AppData\Local\Nauagency\Multi Agent Herdr\agent-environments"
} else {
    Join-Path $env:LOCALAPPDATA "Nauagency\Multi Agent Herdr\agent-environments"
}
$jobsRoot = Join-Path $root "space-jobs"
New-Item -ItemType Directory -Path $jobsRoot -Force | Out-Null
$safeSpace = $SpaceId -replace '[^A-Za-z0-9._-]', '-'
$file = Join-Path $jobsRoot "$safeSpace.json"
$mailboxFile = Join-Path $jobsRoot "$safeSpace-mailbox.json"
$eventsFile = Join-Path $jobsRoot "$safeSpace-events.jsonl"
$policyFile = Join-Path (Join-Path $root "workflow-policies") "$safeSpace.json"

function Read-Policy {
    try { return Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } catch { return $null }
}

function Read-Jobs {
    try {
        $value = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($value -is [array]) { return @($value) }
        if ($null -ne $value) { return @($value) }
    } catch {}
    return @()
}
function Save-JsonAtomic([string]$Path, $Rows, [int]$Depth) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        ConvertTo-Json -InputObject @($Rows) -Depth $Depth | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Save-Jobs($Rows) { Save-JsonAtomic $file $Rows 8 }
function Read-Mailbox {
    try {
        $value = Get-Content -LiteralPath $mailboxFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($value -is [array]) { return @($value) }
        if ($null -ne $value) { return @($value) }
    } catch {}
    return @()
}
function Save-Mailbox($Rows) { Save-JsonAtomic $mailboxFile $Rows 6 }
function Get-LastEventHash {
    try {
        $last = Get-Content -LiteralPath $eventsFile -Tail 1 -Encoding UTF8 -ErrorAction Stop
        if ($last) { return [string](($last | ConvertFrom-Json).hash) }
    } catch {}
    return ""
}
function Write-ControlEvent([string]$Type, [string]$JobId, [string]$Actor, $Data, [string]$CreatedAt) {
    $previousHash = Get-LastEventHash
    $body = [ordered]@{
        id = "event-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
        schemaVersion = 1; spaceId = $SpaceId; type = $Type; jobId = $JobId
        actor = $Actor; createdAt = $CreatedAt; previousHash = $previousHash; data = $Data
    }
    $canonical = ConvertTo-Json -InputObject $body -Compress -Depth 12
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $event = [ordered]@{}
    foreach ($entry in $body.GetEnumerator()) { $event[$entry.Key] = $entry.Value }
    $event.hash = $hash
    Add-Content -LiteralPath $eventsFile -Value (ConvertTo-Json -InputObject $event -Compress -Depth 12) -Encoding UTF8
    return [pscustomobject]$event
}
function Read-ControlEvents([int]$Limit = 300) {
    if (-not (Test-Path -LiteralPath $eventsFile)) { return @() }
    $rows = @()
    foreach ($line in @(Get-Content -LiteralPath $eventsFile -Tail $Limit -Encoding UTF8)) {
        try { if ($line) { $rows += ($line | ConvertFrom-Json) } } catch {}
    }
    return @($rows)
}
function Add-Mailbox([string]$Type, [string]$From, [string]$To, [string]$JobId, [string]$Summary, [string]$CreatedAt) {
    $rows = @(Read-Mailbox)
    $rows += [pscustomobject]@{
        id = "mail-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); type = $Type
        from = $From; to = $To; jobId = $JobId; summary = $Summary; createdAt = $CreatedAt; read = $false
    }
    Save-Mailbox (@($rows) | Select-Object -Last 500)
}
function Set-Field($Object, [string]$Name, $Value) {
    if ($null -ne $Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}
function Add-Attempt($Job, [string]$Address, [string]$Profile, [string]$Now, [string]$Reason) {
    $attempts = @($Job.attempts)
    foreach ($attempt in @($attempts | Where-Object { [string]$_.status -eq "active" })) {
        Set-Field $attempt "status" "superseded"; Set-Field $attempt "endedAt" $Now
    }
    $number = [math]::Max(1, [int]$Job.attempt)
    $entry = [pscustomobject]@{
        id = "attempt-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); number = $number
        assignee = $Address; profile = $Profile; status = "active"; reason = $Reason; startedAt = $Now; endedAt = ""
    }
    Set-Field $Job "attempts" @($attempts + $entry | Select-Object -Last 20)
    Set-Field $Job "activeAttemptId" $entry.id
    return $entry
}
function Close-ActiveAttempt($Job, [string]$Status, [string]$Now) {
    foreach ($attempt in @($Job.attempts | Where-Object { [string]$_.id -eq [string]$Job.activeAttemptId })) {
        Set-Field $attempt "status" $Status; Set-Field $attempt "endedAt" $Now
    }
}
function Refresh-DependencyStates($Rows, [string]$Now) {
    $changed = $false
    foreach ($job in @($Rows | Where-Object { [string]$_.status -eq "blocked" -and [string]$_.planId })) {
        $dependencies = @($job.dependsOn)
        $resolved = @($Rows | Where-Object { [string]$_.planId -eq [string]$job.planId -and [string]$_.taskKey -in $dependencies })
        if ($resolved.Count -ne $dependencies.Count) { continue }
        if (@($resolved | Where-Object { [string]$_.status -in @("failed", "skipped", "abandoned") }).Count) {
            Set-Field $job "status" "skipped"; Set-Field $job "stage" "done"
            Set-Field $job "result" "Skipped because a dependency did not complete successfully."
            Set-Field $job "updatedAt" $Now; $changed = $true
        } elseif (-not @($resolved | Where-Object { [string]$_.status -ne "completed" }).Count) {
            Set-Field $job "status" "queued"; Set-Field $job "stage" "execution"
            Set-Field $job "recoveryNote" "All dependencies completed; released by the deterministic scheduler."
            Set-Field $job "updatedAt" $Now; $changed = $true
        }
    }
    return $changed
}
function Get-Terminal([string]$Address) {
    try { $raw = (& hc get $Address 2>$null | Out-String).Trim(); if ($raw) { return $raw | ConvertFrom-Json } } catch {}
    return $null
}
function Send-TerminalMessage([string]$Address, [string]$Message) {
    # All terminal-backed providers share one delivery contract: insert the
    # message, then confirm the active prompt. Do not branch by model/provider.
    & hc send $Address $Message | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not send a message to agent '$Address'." }
    # hc send already submits, but a TUI may consume Enter before a large paste
    # settles. Confirm once after a short delay so dispatch is provider-neutral.
    Start-Sleep -Milliseconds 300
    & hc keys $Address enter | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not submit the message to agent '$Address'." }
}
function Assert-SpaceWorker([string]$Address) {
    $policy = Read-Policy
    if ($null -eq $policy -or -not $policy.enabled) { throw "Workflow is not configured for this Space." }
    $terminal = Get-Terminal $Address
    if ($null -eq $terminal -or $terminal.state -ne "live") { throw "Agent '$Address' is not running." }
    if ([string]$terminal.labels.'herdr.space' -ne $SpaceId) { throw "Agent '$Address' does not belong to this Space." }
    if ([string]$terminal.labels.'herdr.role' -eq "manager") { throw "Leader cannot dispatch work to itself." }
    if (-not $terminal.labels.'herdr.profile') { throw "Agent '$Address' has no persistent profile." }
    $profileId = [string]$terminal.labels.'herdr.profile'
    if ($profileId -notin @($policy.executorProfileIds)) { throw "Agent '$Address' is not in the configured Gemini executor pool for this Space." }
    if ([string]$terminal.status.state -eq "working") { throw "Agent '$Address' is busy. Choose another agent or wait." }
    if ($profileId -match '^[A-Za-z0-9._-]+$') {
        try {
            $usagePath = Join-Path (Join-Path $root $profileId) ".herdr-usage.json"
            $usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            $minimum = if ($null -ne $policy.limits.minQuotaPercent) { [double]$policy.limits.minQuotaPercent } else { 10 }
            if (($null -ne $usage.fiveHour -and [double]$usage.fiveHour -lt $minimum) -or ($null -ne $usage.week -and [double]$usage.week -lt $minimum)) {
                throw "Agent '$Address' is below the configured quota minimum ($minimum percent). Choose another configured Gemini in this Space."
            }
        } catch [System.Management.Automation.ItemNotFoundException] {}
    }
    return $terminal
}
function Find-SpaceManager {
    try {
        $snapshot = (& hc ls --json 2>$null | Out-String) | ConvertFrom-Json
        foreach ($row in @($snapshot.terminals)) {
            if ($row.state -ne "live") { continue }
            $terminal = Get-Terminal ([string]$row.address)
            if ($null -ne $terminal -and [string]$terminal.labels.'herdr.space' -eq $SpaceId -and [string]$terminal.labels.'herdr.role' -eq "manager") {
                return $terminal
            }
        }
    } catch {}
    return $null
}
function Find-SpaceLead {
    $policy = Read-Policy
    $leadProfileId = [string]$policy.leadProfileId
    if (-not $leadProfileId) { return $null }
    try {
        $snapshot = (& hc ls --json 2>$null | Out-String) | ConvertFrom-Json
        foreach ($row in @($snapshot.terminals)) {
            if ($row.state -ne "live") { continue }
            $terminal = Get-Terminal ([string]$row.address)
            if ($null -ne $terminal -and [string]$terminal.labels.'herdr.space' -eq $SpaceId -and [string]$terminal.labels.'herdr.profile' -eq $leadProfileId) {
                return $terminal
            }
        }
    } catch {}
    return $null
}
function New-Job([string]$Address, [string]$Task, $Terminal, [string]$Now, [string]$RouteMode = "unclassified", [string]$RouteReason = "") {
    [pscustomobject]@{
        schemaVersion = 4; id = "job-{0}-{1}" -f (Get-Date -Format "yyyyMMddHHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 6)); spaceId = $SpaceId
        runId = "run-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); planId = ""; taskKey = ""; title = ""; dependsOn = @()
        requestedBy = "leader"; assignee = $Address; assigneeProfile = [string]$Terminal.labels.'herdr.profile'; assigneeProvider = [string]$Terminal.labels.'herdr.engine.provider'
        status = "queued"; stage = "execution"; task = $Task; result = ""; attempt = 1; resumeCount = 0; backupCount = 0; reviewRound = 0; sameErrorCount = 0; lastGateError = ""
        previousAssignees = @(); recoveryNote = ""; gateStatus = "pending"; artifacts = @(); checkpoints = @(); evidence = @(); reviewFindings = @()
        attempts = @(); activeAttemptId = ""; decisions = @(); pendingDecision = $null; queuedMessages = @(); maxAttempts = 3; timeoutMinutes = 0
        contextProfile = "lean"; executionMode = "local-only"; requiresUserApproval = $true
        routeMode = $RouteMode; routeReason = $RouteReason; routedAt = $Now; createdAt = $Now; updatedAt = $Now
    }
}
function New-QueuedJob([string]$Task, [string]$Now, [string]$RouteMode = "lead-first", [string]$RouteReason = "") {
    [pscustomobject]@{
        schemaVersion = 4; id = "job-{0}-{1}" -f (Get-Date -Format "yyyyMMddHHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 6)); spaceId = $SpaceId
        runId = "run-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); planId = ""; taskKey = ""; title = ""; dependsOn = @()
        requestedBy = "leader"; assignee = ""; assigneeProfile = ""; assigneeProvider = ""
        status = "queued"; stage = "execution"; task = $Task; result = ""; attempt = 1; resumeCount = 0; backupCount = 0; reviewRound = 0; sameErrorCount = 0; lastGateError = ""
        previousAssignees = @(); recoveryNote = "Waiting for an eligible worker in this Space."; gateStatus = "pending"; artifacts = @(); checkpoints = @(); evidence = @(); reviewFindings = @()
        attempts = @(); activeAttemptId = ""; decisions = @(); pendingDecision = $null; queuedMessages = @(); maxAttempts = 3; timeoutMinutes = 0
        contextProfile = "lean"; executionMode = "local-only"; requiresUserApproval = $true
        routeMode = $RouteMode; routeReason = $RouteReason; routedAt = $Now; createdAt = $Now; updatedAt = $Now
    }
}
function Get-DispatchMessage($Job) {
    $routeLine = if ([string]$Job.routeMode -ne "unclassified") { "Routing=$($Job.routeMode). Reason=$($Job.routeReason)`n" } else { "" }
    if ([string]$Job.routeMode -eq "fast-path") {
        return "Leader assigned a LEAN read-only/low-risk task in Space $SpaceId. jobId=$($Job.id). $($Job.task)`n$routeLine`nUse only this existing agent and local files/processes. Do not change product code unless the task explicitly says so. Record concise plan/progress/final checkpoints and source evidence. When the result is ready, use needs-review with a clear report summary; commit and automatic gate are not required for this fast-path task. Do not mark completed yourself and never ask the user directly; use needs-input so Leader can resolve it."
    }
    return "Leader assigned a LEAN implementation context in Space $SpaceId. jobId=$($Job.id). $($Job.task)`n$routeLine`nUse only this existing agent, the assigned local worktree, local files/processes and localhost previews. Update with space-jobs.ps1 update $SpaceId $($Job.id) working. Write checkpoints at plan/progress/handoff/pre-compact/final; register build/typecheck/lint/test/e2e/security/diff evidence and local artifacts. When work and local checks pass, use needs-review with commit=<hash>; checks=passed; changed=<paths>; report=<summary>. Do not mark completed, merge or deploy yourself. Never ask the user directly: use needs-input so Leader can resolve it."
}
function Get-IdleWorkerCandidates([string[]]$ExcludedAddresses = @()) {
    $policy = Read-Policy
    if ($null -eq $policy -or -not $policy.enabled) { return @() }
    $allowed = @($policy.executorProfileIds)
    $candidates = @()
    try {
        $snapshot = (& hc ls --json 2>$null | Out-String) | ConvertFrom-Json
        foreach ($row in @($snapshot.terminals)) {
            $address = [string]$row.address
            if ($row.state -ne "live" -or $address -in $ExcludedAddresses) { continue }
            $terminal = Get-Terminal $address
            if ($null -eq $terminal) { continue }
            $profileId = [string]$terminal.labels.'herdr.profile'
            if ([string]$terminal.labels.'herdr.space' -ne $SpaceId -or [string]$terminal.labels.'herdr.role' -eq "manager" -or $profileId -notin $allowed) { continue }
            try { $verified = Assert-SpaceWorker $address } catch { continue }
            $score = 50.0
            try {
                $usagePath = Join-Path (Join-Path $root $profileId) ".herdr-usage.json"
                $usage = Get-Content -LiteralPath $usagePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
                $values = @($usage.fiveHour, $usage.week) | Where-Object { $null -ne $_ }
                if ($values.Count) { $score = [double](($values | Measure-Object -Minimum).Minimum) }
            } catch {}
            $order = [array]::IndexOf($allowed, $profileId)
            $candidates += [pscustomobject]@{ address = $address; terminal = $terminal; score = $score; order = if ($order -ge 0) { $order } else { 999 } }
        }
    } catch {}
    return @($candidates | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'order'; Ascending = $true })
}

$mutex = [Threading.Mutex]::new($false, "Local\Nauagency.MultiAgentHerdr.SpaceJobs.$safeSpace")
$locked = $false
try {
    $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(10))
    if (-not $locked) { throw "Timed out while updating Space jobs." }
    $jobs = @(Read-Jobs)
    $now = (Get-Date).ToUniversalTime().ToString("o")
    if ($Action -eq "list") { ConvertTo-Json -InputObject $jobs -Compress -Depth 8; exit 0 }
    if ($Action -eq "events") {
        $limit = 300; $parsedLimit = 0
        if ($Values.Count -and [int]::TryParse([string]$Values[0], [ref]$parsedLimit)) { $limit = [math]::Min(2000, [math]::Max(1, $parsedLimit)) }
        ConvertTo-Json -InputObject @(Read-ControlEvents $limit) -Compress -Depth 12
        exit 0
    }
    if ($Action -eq "plan-apply") {
        if ($Values.Count -lt 1) { throw "plan-apply requires a JSON plan file path." }
        $planPath = [IO.Path]::GetFullPath([string]$Values[0])
        if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Plan file does not exist." }
        try { $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw "Plan file is not valid JSON." }
        $idempotencyKey = ([string]$plan.idempotencyKey).Trim()
        if ($idempotencyKey -notmatch '^[A-Za-z0-9._:-]{6,160}$') { throw "Plan idempotencyKey must contain 6 to 160 safe characters." }
        $existingPlan = @($jobs | Where-Object { [string]$_.planKey -eq $idempotencyKey })
        if ($existingPlan.Count) { ConvertTo-Json -InputObject $existingPlan -Compress -Depth 10; exit 0 }
        $specs = @($plan.tasks)
        if (-not $specs.Count -or $specs.Count -gt 100) { throw "Plan must contain 1 to 100 tasks." }
        $keys = @($specs | ForEach-Object { ([string]$_.key).Trim() })
        if (@($keys | Where-Object { $_ -notmatch '^[A-Za-z0-9._-]{1,80}$' }).Count -or @($keys | Select-Object -Unique).Count -ne $keys.Count) {
            throw "Every task key must be unique and contain only letters, numbers, dot, underscore, or dash."
        }
        $indegree = @{}; $dependents = @{}
        foreach ($key in $keys) { $indegree[$key] = 0; $dependents[$key] = @() }
        foreach ($spec in $specs) {
            $key = ([string]$spec.key).Trim(); $dependencies = @($spec.dependsOn | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            if ($key -in $dependencies -or @($dependencies | Where-Object { $_ -notin $keys }).Count) { throw "Task '$key' has an invalid dependency." }
            $dependencies = @($dependencies | Select-Object -Unique)
            $indegree[$key] = $dependencies.Count
            foreach ($dependency in $dependencies) { $dependents[$dependency] = @($dependents[$dependency]) + $key }
        }
        $ready = [Collections.Generic.Queue[string]]::new()
        foreach ($key in $keys) { if ([int]$indegree[$key] -eq 0) { $ready.Enqueue($key) } }
        $visited = 0
        while ($ready.Count) { $key = $ready.Dequeue(); $visited++; foreach ($next in @($dependents[$key])) { $indegree[$next] = [int]$indegree[$next] - 1; if ([int]$indegree[$next] -eq 0) { $ready.Enqueue($next) } } }
        if ($visited -ne $keys.Count) { throw "Plan dependency graph contains a cycle." }

        $planId = "plan-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
        $runId = "run-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10))
        $created = @()
        foreach ($spec in $specs) {
            $key = ([string]$spec.key).Trim(); $title = ([string]$spec.title).Trim(); $description = ([string]$spec.description).Trim()
            if (-not $title -or $title.Length -gt 200 -or -not $description -or $description.Length -gt 12000) { throw "Task '$key' needs a title and description within bounds." }
            $dependencies = @($spec.dependsOn | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
            $routeMode = ([string]$spec.routeMode).Trim(); if (-not $routeMode) { $routeMode = "lead-first" }
            if ($routeMode -notin @("fast-path", "lead-first", "ask-user")) { throw "Task '$key' has an invalid routeMode." }
            $job = New-QueuedJob $description $now $routeMode "Created from an approved structured plan."
            Set-Field $job "runId" $runId; Set-Field $job "planId" $planId; Set-Field $job "planKey" $idempotencyKey
            Set-Field $job "taskKey" $key; Set-Field $job "title" $title; Set-Field $job "dependsOn" $dependencies
            Set-Field $job "status" $(if ($dependencies.Count) { "blocked" } else { "queued" })
            Set-Field $job "stage" $(if ($dependencies.Count) { "planning" } else { "execution" })
            if ($null -ne $spec.maxAttempts) { Set-Field $job "maxAttempts" ([math]::Min(10, [math]::Max(1, [int]$spec.maxAttempts))) }
            if ($null -ne $spec.timeoutMinutes) { Set-Field $job "timeoutMinutes" ([math]::Min(1440, [math]::Max(0, [int]$spec.timeoutMinutes))) }
            Set-Field $job "requiresUserApproval" $(if ($null -ne $spec.requiresUserApproval) { [bool]$spec.requiresUserApproval } else { $true })
            $created += $job
        }
        $jobs = @($jobs + $created) | Select-Object -Last 500
        Save-Jobs $jobs
        Write-ControlEvent "plan.applied" "" "Leader" ([pscustomobject]@{ planId = $planId; runId = $runId; planKey = $idempotencyKey; goal = [string]$plan.goal; taskKeys = $keys }) $now | Out-Null
        foreach ($job in $created) { Write-ControlEvent "task.created" $job.id "Leader" ([pscustomobject]@{ planId = $planId; taskKey = $job.taskKey; dependsOn = $job.dependsOn; status = $job.status }) $now | Out-Null }
        ConvertTo-Json -InputObject $created -Compress -Depth 10
        exit 0
    }
    if ($Action -eq "mailbox") {
        $mail = @(Read-Mailbox)
        if (-not $mail.Count) {
            foreach ($job in @($jobs | Where-Object { $_.result })) {
                $lastCheckpoint = @($_.checkpoints | Select-Object -Last 1)[0]
                $summary = if ($lastCheckpoint.summary) { [string]$lastCheckpoint.summary } else { [string]$job.result }
                $mail += [pscustomobject]@{
                    id = "mail-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); type = "history.imported"
                    from = [string]$job.assignee; to = "Leader"; jobId = [string]$job.id; summary = $summary
                    createdAt = [string]$job.updatedAt; read = $true
                }
            }
            if ($mail.Count) { Save-Mailbox $mail }
        }
        ConvertTo-Json -InputObject $mail -Compress -Depth 6; exit 0
    }
    if ($Action -eq "message") {
        if ($Values.Count -lt 4) { throw "message requires type, from, to, and content." }
        $type = [string]$Values[0]; $from = [string]$Values[1]; $to = [string]$Values[2]
        $content = ($Values[3..($Values.Count - 1)] -join " ").Trim()
        if (-not $content) { throw "Message content cannot be empty." }
        if ($content.Length -gt 12000) { throw "Message content is too long." }
        Add-Mailbox $type $from $to "" $content $now
        @(Read-Mailbox | Select-Object -Last 1) | ConvertTo-Json -Compress -Depth 6
        exit 0
    }
    if ($Action -eq "complete-message") {
        if ($Values.Count -lt 3) { throw "complete-message requires an idempotency key, comma-separated job ids, and the user-facing response." }
        $idempotencyKey = ([string]$Values[0]).Trim()
        if ($idempotencyKey -notmatch '^[A-Za-z0-9._:-]{6,160}$') { throw "Idempotency key must contain 6 to 160 safe characters." }
        $jobIds = @(([string]$Values[1]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        if (-not $jobIds.Count) { throw "At least one exact job id is required." }
        $content = ($Values[2..($Values.Count - 1)] -join " ").Trim()
        if (-not $content -or $content.Length -gt 12000) { throw "User-facing response must contain 1 to 12000 characters." }

        $selected = @($jobs | Where-Object { [string]$_.id -in $jobIds })
        if ($selected.Count -ne $jobIds.Count) { throw "One or more job ids do not exist in this Space." }
        foreach ($job in $selected) {
            $alreadyCompleted = [string]$job.status -eq "completed" -and [string]$job.completionKey -eq $idempotencyKey
            if (-not $alreadyCompleted -and [string]$job.status -ne "needs-review") { throw "Job '$($job.id)' is not waiting for Leader review." }
            if (-not $alreadyCompleted -and [string]::IsNullOrWhiteSpace([string]$job.result)) { throw "Job '$($job.id)' has no submitted result to review." }
            $blocking = @($job.reviewFindings | Where-Object { [string]$_.status -eq "open" -and [string]$_.severity -in @("critical", "high") })
            if ($blocking.Count) { throw "Job '$($job.id)' still has open critical/high review findings." }
            if (-not $alreadyCompleted -and [string]$job.routeMode -ne "fast-path" -and [string]$job.gateStatus -ne "passed") {
                throw "Job '$($job.id)' has not passed its local gate."
            }
        }

        $mail = @(Read-Mailbox)
        $existingResponse = $mail | Where-Object { [string]$_.type -eq "leader.message" -and [string]$_.idempotencyKey -eq $idempotencyKey } | Select-Object -First 1
        $responseId = if ($null -ne $existingResponse) { [string]$existingResponse.id } else { "mail-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)) }
        foreach ($job in $selected) {
            Set-Field $job "status" "completed"
            Set-Field $job "stage" "done"
            Set-Field $job "completionKey" $idempotencyKey
            Set-Field $job "leadDecisionAt" $now
            Set-Field $job "userResponseId" $responseId
            Set-Field $job "updatedAt" $now
            Close-ActiveAttempt $job "completed" $now
            if ([string]$job.result -notmatch '(?i)lead=approved') { Set-Field $job "result" (([string]$job.result).Trim() + "; lead=approved") }
            Write-ControlEvent "task.completed" ([string]$job.id) "Leader" ([pscustomobject]@{ responseId = $responseId; idempotencyKey = $idempotencyKey }) $now | Out-Null
        }
        [void](Refresh-DependencyStates $jobs $now)
        Save-Jobs $jobs

        if ($null -eq $existingResponse) {
            $mail += [pscustomobject]@{
                id = $responseId; type = "leader.message"; from = "Leader"; to = "Bạn"; jobId = ($jobIds -join ",")
                summary = $content; createdAt = $now; read = $false; idempotencyKey = $idempotencyKey
            }
        }
        foreach ($jobId in $jobIds) {
            $accepted = $mail | Where-Object { [string]$_.type -eq "result.accepted" -and [string]$_.jobId -eq $jobId -and [string]$_.idempotencyKey -eq $idempotencyKey } | Select-Object -First 1
            if ($null -eq $accepted) {
                $mail += [pscustomobject]@{
                    id = "mail-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); type = "result.accepted"
                    from = "Leader"; to = "Bạn"; jobId = $jobId; summary = "Leader reviewed and accepted this result."
                    createdAt = $now; read = $false; idempotencyKey = $idempotencyKey; responseId = $responseId
                }
            }
        }
        Save-Mailbox (@($mail) | Select-Object -Last 500)
        [pscustomobject]@{ responseId = $responseId; idempotencyKey = $idempotencyKey; completedJobIds = $jobIds; response = $content } | ConvertTo-Json -Compress -Depth 5
        exit 0
    }
    if ($Action -eq "request-decision") {
        if ($Values.Count -lt 4) { throw "request-decision requires a job id, kind, scope, and summary." }
        $jobId, $kind, $scope = [string]$Values[0], ([string]$Values[1]).ToLowerInvariant(), [string]$Values[2]
        $summary = ($Values[3..($Values.Count - 1)] -join " ").Trim()
        if ($kind -notin @("merge", "deploy", "delete", "external-write", "permission", "product-choice", "other")) { throw "Unsupported decision kind." }
        if (-not $scope -or $scope.Length -gt 1000 -or -not $summary -or $summary.Length -gt 4000) { throw "Decision scope or summary is invalid." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job -or [string]$job.status -in @("completed", "failed", "skipped", "abandoned")) { throw "Job is not active." }
        if ($null -ne $job.pendingDecision -and [string]$job.pendingDecision.status -eq "pending") { throw "This job already has a pending decision." }
        $decision = [pscustomobject]@{ id = "decision-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); kind = $kind; scope = $scope; summary = $summary; status = "pending"; requestedBy = [string]$job.assignee; requestedAt = $now; decidedBy = ""; decidedAt = ""; note = ""; previousStatus = [string]$job.status; previousStage = [string]$job.stage }
        Set-Field $job "pendingDecision" $decision; Set-Field $job "status" "awaiting-approval"; Set-Field $job "stage" "approval"; Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        Write-ControlEvent "decision.requested" $jobId ([string]$job.assignee) $decision $now | Out-Null
        Add-Mailbox "decision.requested" ([string]$job.assignee) "Bạn" $jobId "$kind · $scope · $summary" $now
        $decision | ConvertTo-Json -Compress -Depth 8
        exit 0
    }
    if ($Action -eq "decide") {
        if ($Values.Count -lt 4) { throw "decide requires a job id, decision id, approve|deny, and actor." }
        $jobId, $decisionId, $verdict, $actor = [string]$Values[0], [string]$Values[1], ([string]$Values[2]).ToLowerInvariant(), [string]$Values[3]
        $note = if ($Values.Count -gt 4) { ($Values[4..($Values.Count - 1)] -join " ").Trim() } else { "" }
        if ($verdict -notin @("approve", "deny") -or -not $actor -or $actor.Length -gt 200 -or $note.Length -gt 2000) { throw "Decision verdict, actor, or note is invalid." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        $pending = $job.pendingDecision
        if ($null -eq $pending -or [string]$pending.id -ne $decisionId -or [string]$pending.status -ne "pending") { throw "The exact pending decision was not found." }
        Set-Field $pending "status" $(if ($verdict -eq "approve") { "approved" } else { "denied" }); Set-Field $pending "decidedBy" $actor; Set-Field $pending "decidedAt" $now; Set-Field $pending "note" $note
        Set-Field $job "decisions" @(@($job.decisions) + $pending | Select-Object -Last 40); Set-Field $job "pendingDecision" $null
        $decisionSummary = "Decision $verdict for '$([string]$pending.scope)'."
        if ($note) { $decisionSummary += " $note" }
        $restoreStatus = if ([string]$pending.previousStatus -and [string]$pending.previousStatus -ne "awaiting-approval") { [string]$pending.previousStatus } else { "working" }
        $restoreStage = if ([string]$pending.previousStage -and [string]$pending.previousStage -ne "approval") { [string]$pending.previousStage } else { "execution" }
        Set-Field $job "status" $restoreStatus; Set-Field $job "stage" $restoreStage; Set-Field $job "result" $decisionSummary; Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        Write-ControlEvent "decision.$verdict" $jobId $actor $pending $now | Out-Null
        Add-Mailbox "decision.$verdict" $actor "Leader" $jobId "$([string]$pending.kind) · $([string]$pending.scope)" $now
        [pscustomobject]@{ jobId = $jobId; decision = $pending; status = $job.status } | ConvertTo-Json -Compress -Depth 8
        exit 0
    }
    if ($Action -eq "enqueue") {
        if ($Values.Count -lt 2) { throw "enqueue requires a job id and a message." }
        $jobId = [string]$Values[0]; $message = ($Values[1..($Values.Count - 1)] -join " ").Trim()
        if (-not $message -or $message.Length -gt 12000) { throw "Queued message must contain 1 to 12000 characters." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job -or [string]$job.status -in @("completed", "failed", "skipped", "abandoned")) { throw "Job is not active." }
        $entry = [pscustomobject]@{ id = "queue-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10)); text = $message; status = "pending"; createdAt = $now; deliveredAt = "" }
        Set-Field $job "queuedMessages" @(@($job.queuedMessages) + $entry | Select-Object -Last 50); Set-Field $job "updatedAt" $now
        Save-Jobs $jobs; Write-ControlEvent "message.queued" $jobId "Leader" $entry $now | Out-Null
        $entry | ConvertTo-Json -Compress -Depth 6
        exit 0
    }
    if ($Action -eq "deliver") {
        $delivered = @()
        foreach ($job in @($jobs | Where-Object { $_.assignee -and [string]$_.status -in @("queued", "working", "checking") })) {
            $terminal = Get-Terminal ([string]$job.assignee)
            if ($null -eq $terminal -or [string]$terminal.state -ne "live" -or [string]$terminal.status.state -eq "working") { continue }
            foreach ($entry in @($job.queuedMessages | Where-Object { [string]$_.status -eq "pending" })) {
                try {
                    Send-TerminalMessage ([string]$job.assignee) "QUEUED STEERING for jobId=$($job.id): $([string]$entry.text)"
                    Set-Field $entry "status" "delivered"; Set-Field $entry "deliveredAt" $now; $delivered += $entry
                    Write-ControlEvent "message.delivered" ([string]$job.id) "Scheduler" ([pscustomobject]@{ queueId = $entry.id; assignee = [string]$job.assignee }) $now | Out-Null
                } catch { break }
            }
        }
        if ($delivered.Count) { Save-Jobs $jobs }
        ConvertTo-Json -InputObject $delivered -Compress -Depth 6
        exit 0
    }
    if ($Action -eq "abandon") {
        if ($Values.Count -lt 2) { throw "abandon requires a job id and reason." }
        $jobId = [string]$Values[0]; $reason = ($Values[1..($Values.Count - 1)] -join " ").Trim()
        if (-not $reason -or $reason.Length -gt 4000) { throw "Abandon reason is invalid." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job -or [string]$job.status -in @("completed", "failed", "skipped", "abandoned")) { throw "Job is not active." }
        Close-ActiveAttempt $job "fenced" $now
        Set-Field $job "status" "abandoned"; Set-Field $job "stage" "done"; Set-Field $job "result" $reason; Set-Field $job "updatedAt" $now
        [void](Refresh-DependencyStates $jobs $now)
        Save-Jobs $jobs; Write-ControlEvent "task.abandoned" $jobId "Leader" ([pscustomobject]@{ reason = $reason; note = "This fences the assignment but does not claim the process stopped." }) $now | Out-Null
        $job | ConvertTo-Json -Compress -Depth 8
        exit 0
    }
    if ($Action -eq "recover") {
        $policy = Read-Policy
        $resumeLimit = if ($null -ne $policy.limits.autoResumeLimit) { [int]$policy.limits.autoResumeLimit } else { 1 }
        $live = @{}
        try { $snapshot = (& hc ls --json 2>$null | Out-String) | ConvertFrom-Json; foreach ($terminal in @($snapshot.terminals)) { if ($terminal.state -eq "live") { $live[[string]$terminal.address] = $true } } } catch {}
        $changed = $false
        $jobs = @($jobs | ForEach-Object {
            if ($_.status -in @("queued", "working") -and $_.assignee -and -not $live.ContainsKey([string]$_.assignee)) {
                $changed = $true; $lostAssignee = [string]$_.assignee; $resumeCount = if ($null -ne $_.resumeCount) { [int]$_.resumeCount } else { 0 }
                Close-ActiveAttempt $_ "lost" $now
                if ($resumeCount -lt $resumeLimit) {
                    $_.previousAssignees = @($_.previousAssignees) + [string]$_.assignee; $_.assignee = ""; $_.assigneeProfile = ""; $_.status = "queued"
                    $_.resumeCount = $resumeCount + 1; $_.attempt = [math]::Max(1, [int]$_.attempt) + 1; $_.recoveryNote = "Agent stopped; queued once for reassignment after restart."
                } else { $_.status = "needs-input"; $_.result = "Automatic resume limit reached. User decision is required." }
                $_.updatedAt = $now
                Write-ControlEvent "attempt.lost" ([string]$_.id) "Recovery" ([pscustomobject]@{ previousAssignee = $lostAssignee; resumeCount = [int]$_.resumeCount; status = [string]$_.status }) $now | Out-Null
            }
            $_
        })
        if ($changed) { Save-Jobs $jobs }
        ConvertTo-Json -InputObject $jobs -Compress -Depth 8; exit 0
    }

    if ($Action -eq "auto-dispatch") {
        if ($Values.Count -lt 1) { throw "auto-dispatch requires a task." }
        $task = ($Values -join " ").Trim()
        if (-not $task) { throw "Task cannot be empty." }
        $policy = Read-Policy
        if ($null -eq $policy -or -not $policy.enabled) { throw "Workflow is not configured for this Space." }
        $busyAddresses = @($jobs | Where-Object { $_.assignee -and $_.status -in @("queued", "working", "checking") } | ForEach-Object { [string]$_.assignee })
        $chosen = @(Get-IdleWorkerCandidates $busyAddresses) | Select-Object -First 1
        if ($null -eq $chosen) {
            $job = New-QueuedJob $task $now "lead-first" "Herdr control-plane queued the request until an eligible existing worker becomes idle."
            $jobs = @($jobs + $job) | Select-Object -Last 300
            Save-Jobs $jobs
            Add-Mailbox "task.queued" "Leader" "Worker pool" $job.id $task $now
            $job | ConvertTo-Json -Compress -Depth 8
            exit 0
        }
        $Action = "route-dispatch"
        $Values = @([string]$chosen.address, "lead-first", "Herdr control-plane assigned an existing idle worker; Leader remains coordinator/reviewer.", $task)
    }

    if ($Action -eq "schedule") {
        if (Refresh-DependencyStates $jobs $now) {
            Save-Jobs $jobs
            Write-ControlEvent "scheduler.dependencies-refreshed" "" "Scheduler" ([pscustomobject]@{}) $now | Out-Null
        }
        $assigned = @()
        $reserved = @($jobs | Where-Object { $_.assignee -and $_.status -in @("queued", "working", "checking") } | ForEach-Object { [string]$_.assignee })
        foreach ($job in @($jobs | Where-Object { $_.status -eq "queued" -and -not $_.assignee } | Sort-Object createdAt)) {
            $candidate = @(Get-IdleWorkerCandidates $reserved) | Select-Object -First 1
            if ($null -eq $candidate) { break }
            $terminal = $candidate.terminal
            Set-Field $job "assignee" ([string]$candidate.address)
            Set-Field $job "assigneeProfile" ([string]$terminal.labels.'herdr.profile')
            Set-Field $job "assigneeProvider" ([string]$terminal.labels.'herdr.engine.provider')
            Set-Field $job "recoveryNote" "Assigned by the Herdr scheduler when a worker became available."
            Set-Field $job "updatedAt" $now
            $attempt = Add-Attempt $job ([string]$candidate.address) ([string]$terminal.labels.'herdr.profile') $now "scheduler-assigned"
            Save-Jobs $jobs
            try {
                Send-TerminalMessage ([string]$candidate.address) (Get-DispatchMessage $job)
                Add-Mailbox "task.assigned" "Scheduler" ([string]$candidate.address) $job.id ([string]$job.task) $now
                Write-ControlEvent "attempt.started" $job.id "Scheduler" ([pscustomobject]@{ attemptId = $attempt.id; assignee = [string]$candidate.address; profile = [string]$terminal.labels.'herdr.profile' }) $now | Out-Null
                $reserved += [string]$candidate.address
                $assigned += $job
            } catch {
                Set-Field $job "assignee" ""
                Set-Field $job "assigneeProfile" ""
                Set-Field $job "assigneeProvider" ""
                Set-Field $job "recoveryNote" "Dispatch failed; kept in the durable queue for the next scheduler pass."
                Close-ActiveAttempt $job "dispatch-failed" $now
                Set-Field $job "updatedAt" $now
                Save-Jobs $jobs
                Write-ControlEvent "attempt.dispatch-failed" $job.id "Scheduler" ([pscustomobject]@{ attemptId = $attempt.id; error = $_.Exception.Message }) $now | Out-Null
                break
            }
        }
        ConvertTo-Json -InputObject @($assigned) -Compress -Depth 8
        exit 0
    }

    if ($Action -in @("create", "dispatch", "route-dispatch")) {
        if ($Values.Count -lt 2) { throw "$Action requires an agent address and a task." }
        $address = [string]$Values[0]
        $routeMode = "unclassified"; $routeReason = ""
        if ($Action -eq "route-dispatch") {
            if ($Values.Count -lt 4) { throw "route-dispatch requires address, route mode, quoted route reason, and task." }
            $routeMode = [string]$Values[1]; $routeReason = [string]$Values[2]
            if ($routeMode -eq "leader-first") { $routeMode = "lead-first" }
            if ($routeMode -notin @("fast-path", "lead-first", "ask-user")) { throw "Route mode must be fast-path, leader-first, or ask-user." }
            if (-not $routeReason -or $routeReason.Length -gt 500) { throw "Route reason must contain 1 to 500 characters." }
            $task = ($Values[3..($Values.Count - 1)] -join " ").Trim()
        } else { $task = ($Values[1..($Values.Count - 1)] -join " ").Trim() }
        if (-not $task) { throw "Task cannot be empty." }
        $terminal = Assert-SpaceWorker $address; $job = New-Job $address $task $terminal $now $routeMode $routeReason
        $attempt = Add-Attempt $job $address ([string]$terminal.labels.'herdr.profile') $now "leader-assigned"
        $jobs = @($jobs + $job) | Select-Object -Last 300; Save-Jobs $jobs
        Write-ControlEvent "task.created" $job.id "Leader" ([pscustomobject]@{ runId = $job.runId; routeMode = $job.routeMode; task = $job.task }) $now | Out-Null
        if ($Action -in @("dispatch", "route-dispatch")) {
            Send-TerminalMessage $address (Get-DispatchMessage $job)
            Add-Mailbox "task.assigned" "Leader" $address $job.id $task $now
            Write-ControlEvent "attempt.started" $job.id "Leader" ([pscustomobject]@{ attemptId = $attempt.id; assignee = $address; profile = [string]$terminal.labels.'herdr.profile' }) $now | Out-Null
        }
        $job | ConvertTo-Json -Compress -Depth 8; exit 0
    }

    if ($Action -eq "route") {
        if ($Values.Count -lt 3) { throw "route requires a job id, route mode, and reason." }
        $jobId, $routeMode = [string]$Values[0], [string]$Values[1]
        $routeReason = ($Values[2..($Values.Count - 1)] -join " ").Trim()
        if ($routeMode -eq "leader-first") { $routeMode = "lead-first" }
        if ($routeMode -notin @("fast-path", "lead-first", "ask-user")) { throw "Route mode must be fast-path, leader-first, or ask-user." }
        if (-not $routeReason -or $routeReason.Length -gt 500) { throw "Route reason must contain 1 to 500 characters." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        Set-Field $job "routeMode" $routeMode; Set-Field $job "routeReason" $routeReason; Set-Field $job "routedAt" $now; Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $job | ConvertTo-Json -Compress -Depth 8; exit 0
    }

    if ($Action -eq "gate") {
        if ($Values.Count -lt 2) { throw "gate requires a job id and worktree path." }
        $jobId, $worktree = [string]$Values[0], [IO.Path]::GetFullPath([string]$Values[1])
        if (-not (Test-Path -LiteralPath $worktree -PathType Container)) { throw "Worktree path does not exist." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        if ([string]$job.assignee -eq "") { throw "Job has no assigned Gemini." }
        $gitRoot = (& git -C $worktree rev-parse --show-toplevel 2>$null | Out-String).Trim()
        if (-not $gitRoot) { throw "Automatic checks require a Git worktree." }
        $branch = (& git -C $worktree branch --show-current 2>$null | Out-String).Trim()
        if ($branch -in @("main", "master")) { throw "Refusing to check work performed directly on '$branch'. Use a separate worktree branch." }
        $commit = (& git -C $worktree rev-parse HEAD 2>$null | Out-String).Trim()
        $changed = @(& git -C $worktree show --pretty=format: --name-only HEAD 2>$null | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().Replace('\', '/') } | Where-Object { $_ })
        if (-not $changed.Count) { throw "The latest commit has no changed files." }
        $forbidden = @($changed | Where-Object { $_ -match '(^|/)\.env($|\.)|secret|credential|(^|/)\.git/' })
        if ($forbidden.Count) { throw "Protected paths changed: $($forbidden -join ', '). Stop and ask the user." }

        $commands = @()
        $packageFile = Join-Path $worktree "package.json"
        if (Test-Path -LiteralPath $packageFile) {
            try {
                $package = Get-Content -LiteralPath $packageFile -Raw | ConvertFrom-Json
                $runner = if (Test-Path -LiteralPath (Join-Path $worktree "pnpm-lock.yaml")) { "pnpm" } elseif (Test-Path -LiteralPath (Join-Path $worktree "yarn.lock")) { "yarn" } else { "npm" }
                foreach ($name in @("lint", "typecheck", "test", "build")) {
                    if ($null -ne $package.scripts.$name) {
                        $args = if ($runner -eq "npm") { @("run", $name) } else { @($name) }
                        $commands += [pscustomobject]@{ Name = $runner; Args = $args; Label = $name }
                    }
                }
                if ($null -ne $package.scripts.'test:e2e') {
                    $e2eGate = "D:\Skill-Agent\shared\e2e\scripts\herdr-gate.ps1"
                    if (Test-Path -LiteralPath $e2eGate) {
                        $commands += [pscustomobject]@{ Name = "powershell.exe"; Args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $e2eGate, $worktree); Label = "e2e local strict gate" }
                    }
                }
            } catch { throw "Cannot read package.json for automatic checks." }
        }
        if (Test-Path -LiteralPath (Join-Path $worktree "Cargo.toml")) { $commands += [pscustomobject]@{ Name = "cargo"; Args = @("test"); Label = "cargo test" } }
        if ((Test-Path -LiteralPath (Join-Path $worktree "go.mod"))) { $commands += [pscustomobject]@{ Name = "go"; Args = @("test", "./..."); Label = "go test" } }
        if ((Test-Path -LiteralPath (Join-Path $worktree "pyproject.toml")) -or (Test-Path -LiteralPath (Join-Path $worktree "pytest.ini"))) { $commands += [pscustomobject]@{ Name = "pytest"; Args = @("-q"); Label = "pytest" } }

        if (-not $commands.Count) {
            $job.status = "needs-input"; Set-Field $job "stage" "automatic-gate"; Set-Field $job "gateStatus" "not-configured"; Set-Field $job "worktree" $worktree; Set-Field $job "commit" $commit; Set-Field $job "changedPaths" $changed
            $job.result = "No lint, typecheck, test, or build command was found. Ask the user or Lead to define the required check before review."
            Set-Field $job "updatedAt" $now; Save-Jobs $jobs
            $job | ConvertTo-Json -Compress -Depth 8; exit 3
        }

        $job.status = "checking"; Set-Field $job "stage" "automatic-gate"; Set-Field $job "gateStatus" "running"; Set-Field $job "worktree" $worktree; Set-Field $job "commit" $commit; Set-Field $job "changedPaths" $changed; Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $failed = $null
        $gateEvidence = @()
        foreach ($command in $commands) {
            Push-Location $worktree
            try {
                $output = (& $command.Name @($command.Args) 2>&1 | Out-String)
                $code = $LASTEXITCODE
            } finally { Pop-Location }
            $gateEvidence += [pscustomobject]@{
                id = "evidence-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)); kind = if ($command.Label -match "e2e") { "e2e" } elseif ($command.Label -in @("lint", "typecheck", "test", "build")) { [string]$command.Label } else { "other" }
                status = if ($code -eq 0) { "passed" } else { "failed" }; summary = "$($command.Label) exited with code $code"; source = "automatic-local-gate"
                from = "herdr"; profile = "local-gate"; createdAt = (Get-Date).ToUniversalTime().ToString("o")
            }
            if ($code -ne 0) { $failed = [pscustomobject]@{ Label = $command.Label; Output = $output }; break }
        }
        $existingEvidence = @()
        if ($null -ne $job.evidence) { $existingEvidence = @($job.evidence) }
        Set-Field $job "evidence" @($existingEvidence + $gateEvidence | Select-Object -Last 60)
        if ($null -ne $failed) {
            $tail = (($failed.Output -split "`r?`n") | Select-Object -Last 30) -join "`n"
            $fingerprint = [Convert]::ToBase64String(([Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes("$($failed.Label)`n$tail")))
            $same = if ([string]$job.lastGateError -eq $fingerprint) { [int]$job.sameErrorCount + 1 } else { 1 }
            Set-Field $job "lastGateError" $fingerprint; Set-Field $job "sameErrorCount" $same; Set-Field $job "gateStatus" "failed"; Set-Field $job "stage" "execution"
            if ($same -ge 2) {
                $job.status = "needs-input"; $job.result = "Automatic check '$($failed.Label)' failed twice. Reassign to a configured backup Gemini or hand to Lead."
            } else {
                $job.status = "working"; $job.result = "Automatic check '$($failed.Label)' failed and was returned to the same Gemini."
                Send-TerminalMessage ([string]$job.assignee) "Automatic gate failed for jobId=$jobId at $($failed.Label). Fix in the same worktree and commit again, then ask Manager to rerun gate.`n$tail"
            }
            Set-Field $job "updatedAt" ((Get-Date).ToUniversalTime().ToString("o")); Save-Jobs $jobs
            $job | ConvertTo-Json -Compress -Depth 8; exit 2
        }
        $job.status = "needs-review"; Set-Field $job "stage" "review"; Set-Field $job "gateStatus" "passed"; Set-Field $job "sameErrorCount" 0
        $job.result = "commit=$commit; checks=passed; changed=$($changed -join ','); automatic=$($commands.Count)"
        Set-Field $job "updatedAt" ((Get-Date).ToUniversalTime().ToString("o")); Save-Jobs $jobs
        $job | ConvertTo-Json -Compress -Depth 8; exit 0
    }

    if ($Action -eq "artifact") {
        if ($Values.Count -lt 3) { throw "artifact requires a job id, type, and local URL or file path." }
        $jobId, $artifactType, $artifactValue = [string]$Values[0], [string]$Values[1], [string]$Values[2]
        $label = if ($Values.Count -gt 3) { ($Values[3..($Values.Count - 1)] -join " ").Trim() } else { "Preview" }
        if ($artifactType -notin @("preview", "image", "video", "audio", "file")) { throw "Unsupported artifact type." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        if ($artifactType -eq "preview") {
            try { $uri = [Uri]$artifactValue } catch { throw "Preview must be a valid local URL." }
            if ($uri.Scheme -notin @("http", "https") -or $uri.Host -notin @("localhost", "127.0.0.1", "::1")) { throw "Only localhost preview URLs are allowed." }
        } else {
            $resolved = [IO.Path]::GetFullPath($artifactValue)
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Artifact file does not exist." }
            if ($job.worktree) {
                $worktreeRoot = [IO.Path]::GetFullPath([string]$job.worktree).TrimEnd('\') + '\'
                if (-not $resolved.StartsWith($worktreeRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Artifact file must stay inside the job worktree." }
            }
            $artifactValue = $resolved
        }
        $artifact = [pscustomobject]@{
            id = "artifact-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
            type = $artifactType; value = $artifactValue; label = $label; from = [string]$job.assignee
            profile = [string]$job.assigneeProfile; createdAt = $now
        }
        $current = @()
        if ($null -ne $job.artifacts) { $current = @($job.artifacts) }
        Set-Field $job "artifacts" @($current + $artifact | Select-Object -Last 20)
        Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $artifact | ConvertTo-Json -Compress -Depth 6; exit 0
    }

    if ($Action -eq "checkpoint") {
        if ($Values.Count -lt 3) { throw "checkpoint requires a job id, kind, and summary." }
        $jobId, $kind = [string]$Values[0], [string]$Values[1]
        $summary = ($Values[2..($Values.Count - 1)] -join " ").Trim()
        if ($kind -notin @("plan", "progress", "handoff", "pre-compact", "final")) { throw "Unsupported checkpoint kind." }
        if (-not $summary -or $summary.Length -gt 4000) { throw "Checkpoint summary must contain 1 to 4000 characters." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        $checkpoint = [pscustomobject]@{
            id = "checkpoint-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)); kind = $kind; summary = $summary
            from = [string]$job.assignee; profile = [string]$job.assigneeProfile; createdAt = $now
        }
        $current = @()
        if ($null -ne $job.checkpoints) { $current = @($job.checkpoints) }
        Set-Field $job "checkpoints" @($current + $checkpoint | Select-Object -Last 30)
        Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $checkpoint | ConvertTo-Json -Compress -Depth 6; exit 0
    }

    if ($Action -eq "evidence") {
        if ($Values.Count -lt 4) { throw "evidence requires a job id, kind, status, and summary." }
        $jobId, $kind, $evidenceStatus = [string]$Values[0], [string]$Values[1], [string]$Values[2]
        $summary = ($Values[3..($Values.Count - 1)] -join " ").Trim()
        if ($kind -notin @("build", "typecheck", "lint", "test", "e2e", "security", "diff", "other")) { throw "Unsupported evidence kind." }
        if ($evidenceStatus -notin @("passed", "failed", "not-run")) { throw "Evidence status must be passed, failed, or not-run." }
        if (-not $summary -or $summary.Length -gt 2000) { throw "Evidence summary must contain 1 to 2000 characters." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        $entry = [pscustomobject]@{
            id = "evidence-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)); kind = $kind; status = $evidenceStatus; summary = $summary
            source = "agent-report"; from = [string]$job.assignee; profile = [string]$job.assigneeProfile; createdAt = $now
        }
        $current = @()
        if ($null -ne $job.evidence) { $current = @($job.evidence) }
        Set-Field $job "evidence" @($current + $entry | Select-Object -Last 60)
        Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $entry | ConvertTo-Json -Compress -Depth 6; exit 0
    }

    if ($Action -eq "review") {
        if ($Values.Count -lt 5) { throw "review requires a job id, reviewer profile, severity, evidence key, and title." }
        $jobId, $reviewer, $severity, $evidenceKey = [string]$Values[0], [string]$Values[1], ([string]$Values[2]).ToLowerInvariant(), ([string]$Values[3]).Trim().ToLowerInvariant()
        $title = ($Values[4..($Values.Count - 1)] -join " ").Trim()
        if ($reviewer -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid reviewer profile." }
        $policy = Read-Policy
        if ($null -ne $policy -and [string]$policy.leadProfileId -and $reviewer -ne [string]$policy.leadProfileId) { throw "Only the configured Lead profile may register review findings." }
        if ($severity -notin @("critical", "high", "medium", "low")) { throw "Unsupported review severity." }
        if (-not $evidenceKey -or $evidenceKey.Length -gt 300 -or -not $title -or $title.Length -gt 1000) { throw "Review evidence key or title is invalid." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        $findings = @()
        if ($null -ne $job.reviewFindings) { $findings = @($job.reviewFindings) }
        $existing = $findings | Where-Object { [string]$_.evidenceKey -eq $evidenceKey } | Select-Object -First 1
        $rank = @{ low = 1; medium = 2; high = 3; critical = 4 }
        if ($null -ne $existing) {
            Set-Field $existing "reviewers" @(@($existing.reviewers) + $reviewer | Select-Object -Unique)
            if ($rank[$severity] -gt $rank[[string]$existing.severity]) { Set-Field $existing "severity" $severity }
            Set-Field $existing "updatedAt" $now
        } else {
            $existing = [pscustomobject]@{
                id = "finding-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)); evidenceKey = $evidenceKey; title = $title
                severity = $severity; reviewers = @($reviewer); status = "open"; resolution = ""; createdAt = $now; updatedAt = $now
            }
            $findings = @($findings + $existing | Select-Object -Last 100)
        }
        Set-Field $job "reviewFindings" ([object[]]@($findings))
        Set-Field $job "stage" "review"
        Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $existing | ConvertTo-Json -Compress -Depth 6; exit 0
    }

    if ($Action -eq "resolve-review") {
        if ($Values.Count -lt 3) { throw "resolve-review requires a job id, evidence key, and resolution." }
        $jobId, $evidenceKey = [string]$Values[0], ([string]$Values[1]).Trim().ToLowerInvariant()
        $resolution = ($Values[2..($Values.Count - 1)] -join " ").Trim()
        if (-not $resolution -or $resolution.Length -gt 2000) { throw "Resolution must contain 1 to 2000 characters." }
        $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        if ($null -eq $job) { throw "Unknown job id." }
        $finding = @($job.reviewFindings) | Where-Object { [string]$_.evidenceKey -eq $evidenceKey -and [string]$_.status -eq "open" } | Select-Object -First 1
        if ($null -eq $finding) { throw "Open review finding was not found." }
        Set-Field $finding "status" "resolved"; Set-Field $finding "resolution" $resolution; Set-Field $finding "updatedAt" $now
        Set-Field $job "updatedAt" $now
        Save-Jobs $jobs
        $finding | ConvertTo-Json -Compress -Depth 6; exit 0
    }

    if ($Action -eq "reassign") {
        if ($Values.Count -lt 2) { throw "reassign requires a job id and a new agent address." }
        $jobId, $address = [string]$Values[0], [string]$Values[1]
        $reason = if ($Values.Count -gt 2) { $Values[2..($Values.Count - 1)] -join " " } else { "Reassigned by Manager." }
        $terminal = Assert-SpaceWorker $address; $found = $false
        $policy = Read-Policy
        $maxBackups = if ($null -ne $policy.limits.maxExecutorBackups) { [int]$policy.limits.maxExecutorBackups } else { 2 }
        $jobs = @($jobs | ForEach-Object {
            if ($_.id -eq $jobId) {
                if ($_.status -in @("completed", "failed", "skipped", "abandoned")) { throw "A finished job cannot be reassigned." }
                $backupCount = if ($null -ne $_.backupCount) { [int]$_.backupCount } else { 0 }
                if ($backupCount -ge $maxBackups) { throw "Gemini backup limit reached. Stop and ask the user or hand the job to the configured Lead." }
                if ([int]$_.attempt -ge [int]$_.maxAttempts) { throw "Attempt limit reached. A user decision is required before more work is started." }
                $found = $true; if ($_.assignee) { $_.previousAssignees = @($_.previousAssignees) + [string]$_.assignee }
                Close-ActiveAttempt $_ "superseded" $now
                $_.assignee = $address; $_.assigneeProfile = [string]$terminal.labels.'herdr.profile'; $_.assigneeProvider = [string]$terminal.labels.'herdr.engine.provider'
                $_.status = "queued"; Set-Field $_ "backupCount" ($backupCount + 1); $_.attempt = [math]::Max(1, [int]$_.attempt) + 1; $_.recoveryNote = $reason; $_.updatedAt = $now
                $newAttempt = Add-Attempt $_ $address ([string]$terminal.labels.'herdr.profile') $now "leader-reassigned"
                Write-ControlEvent "attempt.started" ([string]$_.id) "Leader" ([pscustomobject]@{ attemptId = $newAttempt.id; assignee = $address; reason = $reason }) $now | Out-Null
            }
            $_
        })
        if (-not $found) { throw "Unknown job id." }
        Save-Jobs $jobs; $job = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
        Send-TerminalMessage $address "Manager reassigned work in Space $SpaceId. jobId=$jobId. $($job.task)"
        $job | ConvertTo-Json -Compress -Depth 8; exit 0
    }

    if ($Values.Count -lt 2) { throw "update requires a job id and status." }
    $jobId = $Values[0]; $status = $Values[1]
    if ($status -notin @("blocked", "queued", "working", "checking", "needs-review", "needs-input", "awaiting-approval", "completed", "failed", "skipped", "abandoned")) { throw "Invalid job status." }
    $found = $false; $detail = if ($Values.Count -gt 2) { $Values[2..($Values.Count - 1)] -join " " } else { "" }
    $allowed = @{
        blocked = @("queued", "skipped", "failed", "abandoned")
        queued = @("working", "needs-input", "failed", "abandoned")
        working = @("checking", "needs-review", "needs-input", "failed")
        checking = @("working", "needs-review", "needs-input", "failed")
        'needs-review' = @("working", "awaiting-approval", "completed", "needs-input", "failed")
        'needs-input' = @("working", "failed")
        'awaiting-approval' = @("completed", "working", "failed")
    }
    $jobs = @($jobs | ForEach-Object {
        if ($_.id -eq $jobId) {
            $found = $true
            if ($_.status -in @("completed", "failed", "skipped", "abandoned")) { throw "A finished job cannot be changed." }
            if ($status -ne $_.status -and $status -notin @($allowed[[string]$_.status])) { throw "Invalid job transition: $($_.status) -> $status." }
            $isFastPath = [string]$_.routeMode -eq "fast-path"
            if ($status -eq "needs-review" -and -not $isFastPath -and ($detail -notmatch '(?i)commit=\S+' -or $detail -notmatch '(?i)checks=passed')) {
                throw "Review requires a commit and passed automatic checks. Include commit=<hash>; checks=passed."
            }
            if ($status -eq "needs-review" -and $isFastPath -and [string]::IsNullOrWhiteSpace($detail)) {
                throw "Fast-path review requires a result summary."
            }
            if ($status -eq "completed" -and -not $isFastPath -and ($detail -notmatch '(?i)commit=\S+' -or $detail -notmatch '(?i)checks=passed' -or $detail -notmatch '(?i)lead=approved')) {
                throw "Completion requires commit=<hash>; checks=passed; lead=approved. Merge and deploy still require user approval."
            }
            if ($status -eq "completed" -and $isFastPath -and $detail -notmatch '(?i)lead=approved') {
                throw "Fast-path completion requires Leader approval. Include lead=approved."
            }
            if ($status -eq "awaiting-approval") {
                if ([string]$_.gateStatus -ne "passed" -or $detail -notmatch '(?i)lead=approved') {
                    throw "User approval requires a passed local gate and lead=approved."
                }
                $blocking = @($_.reviewFindings | Where-Object { [string]$_.status -eq "open" -and [string]$_.severity -in @("critical", "high") })
                if ($blocking.Count) { throw "Resolve all open critical/high review findings before asking the user for approval." }
            }
            $_.status = $status; $_.result = $detail; $_.updatedAt = $now
            if ($status -eq "checking") { Set-Field $_ "gateStatus" "running" }
            elseif ($status -eq "needs-review") { Set-Field $_ "gateStatus" $(if ($isFastPath) { "not-required" } else { "passed" }); Set-Field $_ "stage" "review" }
            elseif ($status -eq "awaiting-approval") { Set-Field $_ "stage" "approval" }
            elseif ($status -eq "completed") { Set-Field $_ "stage" "done"; Close-ActiveAttempt $_ "completed" $now }
            elseif ($status -in @("failed", "skipped", "abandoned")) { Set-Field $_ "stage" "done"; Close-ActiveAttempt $_ $status $now }
        }
        $_
    })
    if (-not $found) { throw "Unknown job id." }
    if ($status -in @("completed", "failed", "skipped", "abandoned")) { [void](Refresh-DependencyStates $jobs $now) }
    Save-Jobs $jobs
    Write-ControlEvent "task.$status" $jobId "ControlPlane" ([pscustomobject]@{ detail = $detail }) $now | Out-Null
    $updatedJob = $jobs | Where-Object id -eq $jobId | Select-Object -First 1
    if ($status -in @("needs-review", "needs-input")) {
        $manager = Find-SpaceManager
        if ($status -eq "needs-review") {
            $lead = Find-SpaceLead
            if ($null -ne $lead) {
                $reviewRequest = "MAILBOX RESULT: Worker $($updatedJob.assignee) finished jobId=$jobId. You are the user-facing Leader. Read this job's checkpoints/evidence/artifacts. If related child jobs are still active, end the turn and wait for their mailbox results; do not poll terminals. When all related results arrive, resolve contradictions and answer the user once with a concise combined conclusion. Result: $detail"
                Send-TerminalMessage ([string]$lead.address) $reviewRequest
                Add-Mailbox "result.submitted" ([string]$updatedJob.assignee) ([string]$lead.address) $jobId $detail $now
            } elseif ($null -ne $manager) {
                Send-TerminalMessage ([string]$manager.address) "MAILBOX RESULT: Worker completed jobId=$jobId. Synthesize it with any related completed jobs and answer the user once. Do not poll worker terminals. Result: $detail"
                Add-Mailbox "result.submitted" ([string]$updatedJob.assignee) ([string]$manager.address) $jobId $detail $now
            }
        } elseif ($null -ne $manager) {
            $handoff = "MAILBOX BLOCKER: worker $($updatedJob.assignee) reported needs-input for jobId=$jobId. As Leader, resolve it from existing context or another Space worker. Ask the user only for missing authority/product choice or risky external action. Detail: $detail"
            Send-TerminalMessage ([string]$manager.address) $handoff
            Add-Mailbox "worker.blocked" ([string]$updatedJob.assignee) ([string]$manager.address) $jobId $detail $now
        }
    }
    if ($status -eq "completed") {
        Add-Mailbox "result.accepted" "Leader" "Bạn" $jobId $detail $now
    }
    $updatedJob | ConvertTo-Json -Compress -Depth 8
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
