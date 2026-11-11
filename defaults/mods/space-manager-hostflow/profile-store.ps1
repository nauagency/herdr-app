[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("list", "list-all", "delete", "get-models")][string]$Action,
    [Parameter(Position = 1)][AllowEmptyString()][string]$Value = ""
)

$ErrorActionPreference = "Stop"
# The launcher pins this variable to the host-owned shared registry before it
# redirects an isolated profile's LOCALAPPDATA.
$root = if ($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT) {
    [IO.Path]::GetFullPath($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT)
} elseif ($env:NAUAGENCY_HOST_PROFILE) {
    Join-Path $env:NAUAGENCY_HOST_PROFILE "AppData\Local\Nauagency\Multi Agent Herdr\agent-environments"
} else {
    Join-Path $env:LOCALAPPDATA "Nauagency\Multi Agent Herdr\agent-environments"
}
$registryPath = Join-Path $root "engine-instances.json"

function Read-Json([string]$Path) {
    try { if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } } catch { $null }
}

function Format-Iso($Value) {
    if (-not $Value) { return "" }
    try { return ([datetime]$Value).ToUniversalTime().ToString("o") } catch { return [string]$Value }
}

function Decode-JwtPayload([string]$Token) {
    try {
        $part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        while ($part.Length % 4) { $part += '=' }
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json
    } catch { return $null }
}

function Save-ProfileEmail([string]$Directory, [string]$Email) {
    if ($Email) {
        [pscustomobject]@{ email = $Email; checkedAt = (Get-Date).ToUniversalTime().ToString("o") } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $Directory ".herdr-account.json") -Encoding UTF8
    }
    return $Email
}

function Get-ProfileEmail([string]$Directory) {
    $emailCache = Read-Json (Join-Path $Directory ".herdr-account.json")
    if ($null -ne $emailCache -and $emailCache.email) { return [string]$emailCache.email }
    $codex = Read-Json (Join-Path $Directory ".codex\auth.json")
    if ($null -ne $codex -and $null -ne $codex.tokens -and $codex.tokens.id_token) {
        $payload = Decode-JwtPayload ([string]$codex.tokens.id_token)
        if ($null -ne $payload -and $payload.email) { return Save-ProfileEmail $Directory ([string]$payload.email) }
        if ($null -ne $payload -and $payload.preferred_username -match '@') { return Save-ProfileEmail $Directory ([string]$payload.preferred_username) }
    }

    $claude = Read-Json (Join-Path $Directory ".claude\.credentials.json")
    foreach ($value in @($claude.email, $claude.account.email, $claude.user.email)) {
        if ($value -match '@') { return Save-ProfileEmail $Directory ([string]$value) }
    }

    $agy = Join-Path $Directory ".gemini\antigravity-cli"
    if (Test-Path -LiteralPath $agy) {
        $files = @(
            Get-ChildItem -LiteralPath $agy -File -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath (Join-Path $agy "log") -File -ErrorAction SilentlyContinue
        ) | Where-Object { $_.Length -lt 4MB -and ($_.Name -match 'oauth|token|credential|cli.*\.log') }
        foreach ($file in ($files | Sort-Object LastWriteTimeUtc -Descending)) {
            try {
                $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
                $emails = [regex]::Matches($text, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') | ForEach-Object Value
                $email = $emails | Where-Object { $_ -notmatch '@lfjj18\.prod\.google\.com$' } | Select-Object -First 1
                if ($email) { return Save-ProfileEmail $Directory ([string]$email) }
            } catch {}
        }
    }
    return ""
}

function Get-ClaudeAuthStatus([string]$Directory) {
    $saved = @{
        USERPROFILE = $env:USERPROFILE
        HOME = $env:HOME
        APPDATA = $env:APPDATA
        LOCALAPPDATA = $env:LOCALAPPDATA
        CLAUDE_CONFIG_DIR = $env:CLAUDE_CONFIG_DIR
    }
    try {
        $env:USERPROFILE = $Directory
        $env:HOME = $Directory
        $env:APPDATA = Join-Path $Directory "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $Directory "AppData\Local"
        $env:CLAUDE_CONFIG_DIR = Join-Path $Directory ".claude"
        $raw = (& claude auth status --json 2>$null | Out-String)
        if ($raw.Trim()) { return $raw | ConvertFrom-Json }
    } catch {}
    finally {
        $env:USERPROFILE = $saved.USERPROFILE
        $env:HOME = $saved.HOME
        $env:APPDATA = $saved.APPDATA
        $env:LOCALAPPDATA = $saved.LOCALAPPDATA
        $env:CLAUDE_CONFIG_DIR = $saved.CLAUDE_CONFIG_DIR
    }
    return $null
}

function Get-ProfileUsage([string]$Directory, [string]$Family) {
    $cachePath = Join-Path $Directory ".herdr-usage.json"
    $cache = Read-Json $cachePath
    if ($null -ne $cache -and $cache.checkedAt) {
        try { if (((Get-Date).ToUniversalTime() - ([datetime]$cache.checkedAt).ToUniversalTime()).TotalSeconds -lt 90) { return $cache } } catch {}
    }
    if ($Family -ne "codex") {
        if ($cache) { return $cache }
        return [pscustomobject]@{ status = "unsupported"; fiveHour = $null; week = $null; model = ""; checkedAt = $null; fiveHourResetAt = $null; weekResetAt = $null }
    }
    $auth = Read-Json (Join-Path $Directory ".codex\auth.json")
    if ($null -eq $auth -or $null -eq $auth.tokens -or -not $auth.tokens.access_token) {
        if ($cache) { return $cache }
        return [pscustomobject]@{ status = "unknown"; fiveHour = $null; week = $null; model = "codex"; checkedAt = $null; fiveHourResetAt = $null; weekResetAt = $null }
    }
    try {
        $response = Invoke-RestMethod -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers @{ Authorization = "Bearer $($auth.tokens.access_token)" } -TimeoutSec 12
        $five = if ($null -ne $response.rate_limit.primary_window.used_percent) { [math]::Max(0, [math]::Round(100 - [double]$response.rate_limit.primary_window.used_percent)) } else { $null }
        $week = if ($null -ne $response.rate_limit.secondary_window.used_percent) { [math]::Max(0, [math]::Round(100 - [double]$response.rate_limit.secondary_window.used_percent)) } else { $null }
        function Reset-Time($Window) {
            $raw = if ($Window.reset_at) { $Window.reset_at } elseif ($Window.resets_at) { $Window.resets_at } else { $null }
            if ($raw) {
                try {
                    if ([string]$raw -match '^\d+(\.\d+)?$') { return [DateTimeOffset]::FromUnixTimeSeconds([long][double]$raw).UtcDateTime.ToString("o") }
                    return ([datetime]$raw).ToUniversalTime().ToString("o")
                } catch {}
            }
            if ($Window.reset_after_seconds) {
                try { return (Get-Date).ToUniversalTime().AddSeconds([double]$Window.reset_after_seconds).ToString("o") } catch {}
            }
            return $null
        }
        $cache = [pscustomobject]@{
            status = "ok"
            fiveHour = $five
            week = $week
            model = "codex"
            checkedAt = (Get-Date).ToUniversalTime().ToString("o")
            fiveHourResetAt = Reset-Time $response.rate_limit.primary_window
            weekResetAt = Reset-Time $response.rate_limit.secondary_window
        }
        $cache | ConvertTo-Json -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8
        return $cache
    } catch {
        if ($cache) { return $cache }
        return [pscustomobject]@{ status = "unavailable"; fiveHour = $null; week = $null; model = "codex"; checkedAt = (Get-Date).ToUniversalTime().ToString("o"); fiveHourResetAt = $null; weekResetAt = $null }
    }
}

function Resolve-InstanceDirectory([string]$Id) {
    $candidate = Join-Path $root $Id
    $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -ne $Id) {
        throw "Invalid engine instance id."
    }
    return $resolved
}

function Get-InstanceModels([string]$Directory, [string]$Provider, [bool]$Authenticated) {
    $cachePath = Join-Path $Directory ".herdr-models.json"
    $cache = Read-Json $cachePath
    if ($cache.schemaVersion -eq 2 -and $cache.checkedAt) {
        try { if (((Get-Date).ToUniversalTime() - ([datetime]$cache.checkedAt).ToUniversalTime()).TotalMinutes -lt 5) { return $cache } } catch {}
    }
    if (-not $Authenticated -or $Provider -ne "antigravity") {
        return [pscustomobject]@{ provider = $Provider; source = "unavailable"; checkedAt = (Get-Date).ToUniversalTime().ToString("o"); models = @() }
    }
    $names = @("USERPROFILE", "HOME", "APPDATA", "LOCALAPPDATA", "ANTIGRAVITY_GEMINI_DIR", "ANTIGRAVITY_APP_DATA_DIR", "ANTIGRAVITY_EXECUTABLE_DATA_DIR", "SSH_CONNECTION", "SSH_TTY", "AGY_CLI_INTERACTIVE_HEADLESS")
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, "Process") }
    try {
        $geminiDir = Join-Path $Directory ".gemini"
        $agyDir = Join-Path $geminiDir "antigravity-cli"
        $env:USERPROFILE = $Directory
        $env:HOME = $Directory
        $env:APPDATA = Join-Path $Directory "AppData\Roaming"
        $env:LOCALAPPDATA = Join-Path $Directory "AppData\Local"
        $env:ANTIGRAVITY_GEMINI_DIR = $geminiDir
        $env:ANTIGRAVITY_APP_DATA_DIR = $agyDir
        $env:ANTIGRAVITY_EXECUTABLE_DATA_DIR = $agyDir
        $env:SSH_CONNECTION = "127.0.0.1 1 127.0.0.1 1"
        $env:SSH_TTY = "/dev/pts/0"
        $env:AGY_CLI_INTERACTIVE_HEADLESS = "true"
        $raw = (& agy models 2>$null | Out-String)
        $models = @($raw -split "`r?`n" | ForEach-Object {
            $match = [regex]::Match($_.Trim(), '^([^\s]+)\s+(.+)$')
            if ($match.Success -and $match.Groups[1].Value -match '-(low|medium|high|xhigh|max)$') {
                [pscustomobject]@{ id = $match.Groups[1].Value; label = ($match.Groups[2].Value -replace '\s*\((Low|Medium|High|XHigh|Max)\)\s*$', '') }
            }
        })
        $result = [pscustomobject]@{ schemaVersion = 2; provider = $Provider; source = "instance"; checkedAt = (Get-Date).ToUniversalTime().ToString("o"); models = $models }
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cachePath -Encoding UTF8
        return $result
    } catch {
        if ($cache) { return $cache }
        return [pscustomobject]@{ provider = $Provider; source = "error"; checkedAt = (Get-Date).ToUniversalTime().ToString("o"); models = @() }
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], "Process") }
    }
}

if ($Action -eq "get-models") {
    $directory = Resolve-InstanceDirectory $Value
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Unknown engine instance." }
    $meta = Read-Json (Join-Path $directory "environment.json")
    $provider = if ($meta.provider) { [string]$meta.provider } elseif ($meta.agentFamily) { [string]$meta.agentFamily } else { [string]$meta.agent }
    $claudeStatus = if ($provider -eq "claude") { Get-ClaudeAuthStatus $directory } else { $null }
    $authenticated = if ($provider -eq "claude") { $claudeStatus.loggedIn -eq $true } elseif ($provider -eq "codex") {
        $auth = Read-Json (Join-Path $directory ".codex\auth.json"); [bool]($auth.tokens.access_token -or $auth.access_token)
    } elseif ($provider -eq "antigravity") {
        $token = Join-Path $directory ".gemini\antigravity-cli\antigravity-oauth-token"; [bool]((Test-Path -LiteralPath $token) -and (Get-Item -LiteralPath $token).Length -gt 16)
    } else { $false }
    Get-InstanceModels $directory $provider $authenticated | ConvertTo-Json -Compress -Depth 6
    exit 0
}

if ($Action -in @("list", "list-all")) {
    $items = @(
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $meta = Read-Json (Join-Path $_.FullName "environment.json")
            if ($null -eq $meta -or ($Action -eq "list" -and [string]$meta.spaceId -ne $Value)) { return }
            $lock = Read-Json (Join-Path $_.FullName "session.lock.json")
            $running = $false
            if ($null -ne $lock -and $lock.pid) { try { $running = $null -ne (Get-Process -Id ([int]$lock.pid) -ErrorAction Stop) } catch {} }
            $family = if ($meta.provider) { [string]$meta.provider } elseif ($meta.agentFamily) { [string]$meta.agentFamily } else { [string]$meta.agent }
            $instanceId = if ($meta.instanceId) { [string]$meta.instanceId } else { [string]$meta.id }
            $claudeStatus = if ($family -eq "claude") { Get-ClaudeAuthStatus $_.FullName } else { $null }
            $profileEmail = if ($null -ne $claudeStatus -and $claudeStatus.email -match '@') {
                Save-ProfileEmail $_.FullName ([string]$claudeStatus.email)
            } else { Get-ProfileEmail $_.FullName }
            $isAuthenticated = if ($family -eq "claude") {
                $null -ne $claudeStatus -and $claudeStatus.loggedIn -eq $true
            } elseif ($family -eq "codex") {
                Test-Path -LiteralPath (Join-Path $_.FullName ".codex\auth.json")
            } elseif ($family -eq "antigravity") {
                Test-Path -LiteralPath (Join-Path $_.FullName ".gemini\antigravity-cli\antigravity-oauth-token")
            } else { $false }
            $login = Read-Json (Join-Path $_.FullName ".herdr-login-state.json")
            $runtime = Read-Json (Join-Path $_.FullName ".herdr-runtime-state.json")
            $loginState = if ($isAuthenticated) { "authenticated" } elseif ($login.state -in @("waiting", "failed")) { [string]$login.state } else { "signed-out" }
            $lifecycle = if ($loginState -eq "waiting") { "awaiting-user" } elseif ($loginState -eq "failed" -or ($runtime.state -eq "error" -and -not $running)) { "error" } elseif ($running) { "starting" } elseif ($isAuthenticated) { "needs-restart" } else { "signed-out" }
            if (-not $meta.schemaVersion -or [int]$meta.schemaVersion -lt 2 -or -not $meta.instanceId -or -not $meta.provider) {
                $meta | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 2 -Force
                $meta | Add-Member -NotePropertyName kind -NotePropertyValue "engine-instance" -Force
                $meta | Add-Member -NotePropertyName instanceId -NotePropertyValue $instanceId -Force
                $meta | Add-Member -NotePropertyName provider -NotePropertyValue $family -Force
                $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $_.FullName "environment.json") -Encoding UTF8
            }
            [pscustomobject]@{
                id = $instanceId
                instanceId = $instanceId
                provider = $family
                agent = [string]$meta.agent
                agentFamily = [string]$meta.agentFamily
                spaceId = [string]$meta.spaceId
                email = $profileEmail
                usage = Get-ProfileUsage $_.FullName $family
                authenticated = [bool]$isAuthenticated
                loginState = $loginState
                loginError = [string]$login.error
                runtimeError = [string]$runtime.error
                lifecycle = $lifecycle
                createdAt = Format-Iso $meta.createdAt
                lastUsedAt = Format-Iso $meta.lastUsedAt
                running = $running
                command = [string]$meta.command
                arguments = @($meta.arguments)
                requestedModel = [string]$meta.requestedModel
                requestedEffort = [string]$meta.requestedEffort
                runtimeModel = [string]$runtime.model
                runtimeEffort = [string]$runtime.effort
            }
        }
    )
    $oldRegistry = Read-Json $registryPath
    $customNames = @{}
    foreach ($row in @($oldRegistry.instances)) { if ($row.id) { $customNames[[string]$row.id] = [string]$row.displayName } }
    $registryRows = @($items | ForEach-Object {
        $custom = $customNames[[string]$_.id]
        [pscustomobject]@{ id = $_.id; provider = $_.provider; displayName = if ($custom -and $custom -ne $_.provider) { $custom } elseif ($_.email) { $_.email } else { $_.provider }; email = $_.email; directory = $_.id; createdAt = $_.createdAt; lastUsedAt = $_.lastUsedAt; loginState = $_.loginState }
    })
    [ordered]@{ version = 1; updatedAt = (Get-Date).ToUniversalTime().ToString("o"); instances = $registryRows } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $registryPath -Encoding UTF8
    ConvertTo-Json -InputObject $items -Compress -Depth 5
    exit 0
}

$resolved = Resolve-InstanceDirectory $Value
if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { exit 0 }
$lock = Read-Json (Join-Path $resolved "session.lock.json")
if ($null -ne $lock -and $lock.pid) {
    $stillRunning = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try { $stillRunning = $null -ne (Get-Process -Id ([int]$lock.pid) -ErrorAction Stop) } catch { $stillRunning = $false }
        if (-not $stillRunning) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($stillRunning) { throw "Profile is still running after the agent was asked to stop." }
}
Remove-Item -LiteralPath $resolved -Recurse -Force
$registry = Read-Json $registryPath
$kept = @($registry.instances | Where-Object { [string]$_.id -ne $Value })
[ordered]@{ version = 1; updatedAt = (Get-Date).ToUniversalTime().ToString("o"); instances = $kept } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $registryPath -Encoding UTF8
