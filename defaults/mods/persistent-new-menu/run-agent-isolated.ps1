[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$AgentKey,
    [Parameter(Position = 1)][AllowEmptyString()][string]$SpaceId = "",
    [Parameter(Position = 2)][ValidateSet("worker", "manager")][string]$Role = "worker",
    [Parameter(Position = 3)][AllowEmptyString()][string]$PreferredProfileId = "",
    [Parameter(Mandatory, Position = 4)][ValidateNotNullOrEmpty()][string]$AgentCommand,
    [Parameter(Position = 5, ValueFromRemainingArguments)][string[]]$AgentArguments = @()
)

$ErrorActionPreference = "Stop"
$forceNewInstance = $PreferredProfileId -eq "__new__"
if ($forceNewInstance) { $PreferredProfileId = "" }
$commandInfo = Get-Command -Name $AgentCommand -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
$resolvedCommand = if ($commandInfo.Path) { $commandInfo.Path } else { $commandInfo.Source }

$hostProfile = $env:USERPROFILE
$hostHome = $env:HOME
$hostAppData = $env:APPDATA
$hostLocalAppData = $env:LOCALAPPDATA
$environmentRoot = if ($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT) {
    [IO.Path]::GetFullPath($env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT)
} else {
    Join-Path $hostLocalAppData "Nauagency\Multi Agent Herdr\agent-environments"
}
$safeAgentKey = $AgentKey -replace '[^A-Za-z0-9._-]', '-'
$commandLeaf = [IO.Path]::GetFileNameWithoutExtension($resolvedCommand).ToLowerInvariant()
$agentFamily = if ($Role -eq "manager" -and $AgentKey -like "manager-*") {
    switch ($commandLeaf) {
        "agy" { "antigravity" }
        "codex" { "codex" }
        "claude" { "claude" }
        default { $AgentKey }
    }
} else { $AgentKey }

# Older profiles may contain a single null/empty argument. Permission flags are
# owned by the Space, so remove any value persisted by an earlier launch before
# applying the Space's current setting below.
$cleanArguments = [Collections.Generic.List[string]]::new()
for ($argumentIndex = 0; $argumentIndex -lt $AgentArguments.Count; $argumentIndex++) {
    $argument = [string]$AgentArguments[$argumentIndex]
    if ([string]::IsNullOrWhiteSpace($argument)) { continue }
    if ($argument -in @("--approve-for-me", "--dangerously-bypass-approvals-and-sandbox", "--dangerously-skip-permissions")) { continue }
    if ($argument -in @("--ask-for-approval", "--sandbox", "--permission-mode", "--mode")) {
        if ($argumentIndex + 1 -lt $AgentArguments.Count) { $argumentIndex++ }
        continue
    }
    $cleanArguments.Add($argument)
}
$AgentArguments = @($cleanArguments)

# Each Space has one consistent approval level for every engine instance.
# Defaults to automatic review so routine project work does not repeatedly
# interrupt the user. Explicit command-line permission flags still win.
$approvalMode = "auto"
try {
    $sharedPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\shared.json"))
    if (Test-Path -LiteralPath $sharedPath) {
        # Windows PowerShell's ConvertFrom-Json rejects Herdr state when any
        # unrelated object contains an empty property name. JavaScriptSerializer
        # handles the full file and returns dictionaries we can index safely.
        Add-Type -AssemblyName System.Web.Extensions
        $jsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $jsonSerializer.MaxJsonLength = [int]::MaxValue
        $sharedState = $jsonSerializer.DeserializeObject((Get-Content -LiteralPath $sharedPath -Raw))
        $spaceSettings = $sharedState["space-manager.config.v1"][$SpaceId]
        if ([string]$spaceSettings["approvalMode"] -in @("ask", "auto", "full")) {
            $approvalMode = [string]$spaceSettings["approvalMode"]
        }
    }
} catch {}

if ($agentFamily -eq "codex") {
    if ($approvalMode -eq "ask") { $AgentArguments += @("--sandbox", "workspace-write", "--ask-for-approval", "on-request") }
    elseif ($approvalMode -eq "full") { $AgentArguments += "--dangerously-bypass-approvals-and-sandbox" }
    else { $AgentArguments += @("--sandbox", "workspace-write", "--approve-for-me") }
    # Isolated CODEX_HOME paths are intentionally descriptive and can exceed
    # Windows' AF_UNIX socket path limit when Codex appends its daemon socket.
    # Each Herdr profile is already isolated, so the shared daemon is neither
    # needed nor desirable here.
    if ($AgentArguments -notcontains "--no-daemon") { $AgentArguments += "--no-daemon" }
} elseif ($agentFamily -eq "claude") {
    if ($approvalMode -eq "ask") { $AgentArguments += @("--permission-mode", "manual") }
    elseif ($approvalMode -eq "full") { $AgentArguments += "--dangerously-skip-permissions" }
    else { $AgentArguments += @("--permission-mode", "auto") }
} elseif ($agentFamily -eq "antigravity") {
    if ($approvalMode -eq "ask") { $AgentArguments += @("--mode", "accept-edits") }
    elseif ($approvalMode -eq "full") { $AgentArguments += "--dangerously-skip-permissions" }
    else { $AgentArguments += @("--mode", "auto") }
}
$requestedModel = "default"
$requestedEffort = ""
for ($i = 0; $i -lt $AgentArguments.Count; $i++) {
    if ($AgentArguments[$i] -eq "--model" -and $i + 1 -lt $AgentArguments.Count) { $requestedModel = [string]$AgentArguments[$i + 1] }
    if ($AgentArguments[$i] -eq "--effort" -and $i + 1 -lt $AgentArguments.Count) { $requestedEffort = [string]$AgentArguments[$i + 1] }
    if ($AgentArguments[$i] -eq "-c" -and $i + 1 -lt $AgentArguments.Count -and $AgentArguments[$i + 1] -match '^model_reasoning_effort=(.+)$') {
        $requestedEffort = $Matches[1].Trim('"')
    }
}
if (-not $requestedEffort -and $requestedModel -match '-(low|medium|high|xhigh|max)$') { $requestedEffort = $Matches[1] }
$poolStatePath = Join-Path $environmentRoot "profile-pool.json"
$engineRegistryPath = Join-Path $environmentRoot "engine-instances.json"
$currentBoot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()
$currentBootUtc = $currentBoot.ToString("o")
$profileLockPath = $null
$processStartUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString("o")

New-Item -ItemType Directory -Path $environmentRoot -Force | Out-Null

function Read-JsonFile([string]$Path) {
    try {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        }
    } catch {}
    return $null
}

function Update-EngineRegistry([hashtable]$Instance) {
    $registry = Read-JsonFile $engineRegistryPath
    $rows = @()
    if ($null -ne $registry -and $null -ne $registry.instances) {
        $rows = @($registry.instances | Where-Object { [string]$_.id -ne [string]$Instance.id })
    }
    $rows += [pscustomobject]$Instance
    [ordered]@{
        version = 1
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        instances = @($rows | Sort-Object createdAt, id)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $engineRegistryPath -Encoding UTF8
}

function Set-LoginState([string]$State, [string]$ErrorMessage = "") {
    if (-not $profileDir) { return }
    [ordered]@{
        state = $State
        provider = $agentFamily
        error = $ErrorMessage
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $profileDir ".herdr-login-state.json") -Encoding UTF8
}

function Set-RuntimeState([string]$State, [string]$ErrorMessage = "") {
    if (-not $profileDir) { return }
    [ordered]@{
        state = $State
        provider = $agentFamily
        model = $requestedModel
        effort = $requestedEffort
        error = $ErrorMessage
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $profileDir ".herdr-runtime-state.json") -Encoding UTF8
}

function Open-LoginPage([string]$Url) {
    # Herdr's terminal does not dispatch hyperlink clicks. Open Chrome directly
    # and leave authentication output entirely to the agent CLI.
    try {
        $chrome = Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
        if (-not $chrome) {
            $chromeCandidates = @(
                (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
                (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
                (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
            )
            $chrome = $chromeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        }
        if ($chrome) {
            Start-Process -FilePath $chrome -ArgumentList $Url | Out-Null
        } else {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $Url
            $startInfo.UseShellExecute = $true
            [Diagnostics.Process]::Start($startInfo) | Out-Null
        }
    } catch {}
}

function Test-ProfileLocked([string]$Directory) {
    $lockPath = Join-Path $Directory "session.lock.json"
    $lock = Read-JsonFile $lockPath
    if ($null -eq $lock) {
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    try {
        $lockBoot = ([datetime]$lock.bootUtc).ToUniversalTime()
        $process = Get-Process -Id ([int]$lock.pid) -ErrorAction Stop
        if ($lockBoot -eq $currentBoot -and $null -ne $process) {
            return $true
        }
    } catch {}

    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    return $false
}

function Get-AuthenticationScore([string]$Directory, [string]$Key) {
    switch ($Key) {
        "codex" {
            $auth = Join-Path $Directory ".codex\auth.json"
            if ((Test-Path -LiteralPath $auth) -and (Get-Item -LiteralPath $auth).Length -gt 16) { return 10 }
        }
        "claude" {
            foreach ($name in @(".credentials.json", ".config.json", ".claude.json")) {
                $accountFile = Join-Path (Join-Path $Directory ".claude") $name
                if ((Test-Path -LiteralPath $accountFile) -and (Get-Item -LiteralPath $accountFile).Length -gt 16) { return 10 }
            }
        }
        "antigravity" {
            $token = Join-Path $Directory ".gemini\antigravity-cli\antigravity-oauth-token"
            if ((Test-Path -LiteralPath $token) -and (Get-Item -LiteralPath $token).Length -gt 16) { return 10 }
        }
    }
    return 0
}

$poolState = Read-JsonFile $poolStatePath
if ($null -eq $poolState) {
    $poolState = [ordered]@{ version = 1; installedBootUtc = $currentBootUtc; installedAt = (Get-Date).ToUniversalTime().ToString("o") }
    $poolState | ConvertTo-Json | Set-Content -LiteralPath $poolStatePath -Encoding UTF8
}
$installedBoot = ([datetime]$poolState.installedBootUtc).ToUniversalTime()
$reuseExistingProfiles = $installedBoot -ne $currentBoot

$mutex = [Threading.Mutex]::new($false, "Local\Nauagency.MultiAgentHerdr.AgentProfiles")
$hasMutex = $false
try {
    try { $hasMutex = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
    catch [Threading.AbandonedMutexException] { $hasMutex = $true }
    if (-not $hasMutex) { throw "Timed out while reserving an agent profile." }

    $profileDir = $null
    if ($PreferredProfileId) {
        $preferred = Join-Path $environmentRoot $PreferredProfileId
        $resolvedRoot = [IO.Path]::GetFullPath($environmentRoot).TrimEnd('\') + '\'
        $resolvedPreferred = [IO.Path]::GetFullPath($preferred)
        $preferredMetadata = Read-JsonFile (Join-Path $resolvedPreferred "environment.json")
        $preferredFamily = if ($preferredMetadata.agentFamily) { [string]$preferredMetadata.agentFamily } else { [string]$preferredMetadata.agent }
        if ($resolvedPreferred.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedPreferred) -eq $PreferredProfileId -and
            (Test-Path -LiteralPath $resolvedPreferred -PathType Container) -and
            $preferredFamily -eq $agentFamily -and
            -not (Test-ProfileLocked $resolvedPreferred)) {
            $profileDir = $resolvedPreferred
        }
        if (-not $profileDir) { throw "The selected engine instance is unavailable, already running, or belongs to another provider." }
    }
    $candidates = if (-not $profileDir -and -not $forceNewInstance) { foreach ($directory in Get-ChildItem -LiteralPath $environmentRoot -Directory -ErrorAction SilentlyContinue) {
        $metadataPath = Join-Path $directory.FullName "environment.json"
        $metadata = Read-JsonFile $metadataPath
        if ($null -eq $metadata -or [string]$metadata.agent -ne $AgentKey -or (Test-ProfileLocked $directory.FullName)) { continue }
        if ([string]$metadata.spaceId -ne $SpaceId) { continue }
        if (-not $reuseExistingProfiles -and $metadata.reusable -ne $true) { continue }
        $lastUsed = if ($metadata.lastUsedAt) { [datetime]$metadata.lastUsedAt } elseif ($metadata.createdAt) { [datetime]$metadata.createdAt } else { $directory.LastWriteTimeUtc }
        [pscustomobject]@{
            Directory = $directory.FullName
            AuthenticationScore = Get-AuthenticationScore $directory.FullName $agentFamily
            LastUsed = $lastUsed
        }
    } }
    if (-not $profileDir) { $profileDir = ($candidates | Sort-Object AuthenticationScore, LastUsed -Descending | Select-Object -First 1).Directory }

    if (-not $profileDir) {
        $slot = 1
        do {
            $environmentId = "{0}-slot-{1:d3}" -f $safeAgentKey, $slot
            $profileDir = Join-Path $environmentRoot $environmentId
            $slot++
        } while (Test-Path -LiteralPath $profileDir)
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    $environmentId = Split-Path -Leaf $profileDir
    $roamingDir = Join-Path $profileDir "AppData\Roaming"
    $localDir = Join-Path $profileDir "AppData\Local"
    foreach ($dir in @($profileDir, $roamingDir, $localDir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $metadataPath = Join-Path $profileDir "environment.json"
    $existingMetadata = Read-JsonFile $metadataPath
    $createdAt = if ($existingMetadata.createdAt) { ([datetime]$existingMetadata.createdAt).ToUniversalTime().ToString("o") } else { (Get-Date).ToUniversalTime().ToString("o") }
    $metadata = [ordered]@{
        schemaVersion = 2
        kind = "engine-instance"
        id = $environmentId
        instanceId = $environmentId
        provider = $agentFamily
        agent = $AgentKey
        agentFamily = $agentFamily
        spaceId = $SpaceId
        createdAt = $createdAt
        lastUsedAt = (Get-Date).ToUniversalTime().ToString("o")
        command = $resolvedCommand
        arguments = @($AgentArguments)
        requestedModel = $requestedModel
        requestedEffort = $requestedEffort
        reusable = $true
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    $existingRegistry = Read-JsonFile $engineRegistryPath
    $existingInstance = @($existingRegistry.instances | Where-Object { [string]$_.id -eq $environmentId } | Select-Object -First 1)
    $existingEmail = if ($existingInstance.Count) { [string]$existingInstance[0].email } else { "" }
    $existingName = if ($existingInstance.Count) { [string]$existingInstance[0].displayName } else { "" }
    Update-EngineRegistry ([ordered]@{
        id = $environmentId
        provider = $agentFamily
        displayName = if ($existingName) { $existingName } else { $agentFamily }
        email = $existingEmail
        directory = $environmentId
        createdAt = $createdAt
        lastUsedAt = [string]$metadata.lastUsedAt
    })

    $profileLockPath = Join-Path $profileDir "session.lock.json"
    [ordered]@{
        pid = $PID
        processStartUtc = $processStartUtc
        bootUtc = $currentBootUtc
        agent = $AgentKey
    } | ConvertTo-Json | Set-Content -LiteralPath $profileLockPath -Encoding UTF8
} finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

$env:NAUAGENCY_AGENT_ENVIRONMENT_ID = $environmentId
$env:NAUAGENCY_ENGINE_INSTANCE_ID = $environmentId
$env:NAUAGENCY_HOST_PROFILE = $hostProfile
$env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT = $environmentRoot
$env:NAUAGENCY_APPROVAL_MODE = $approvalMode

# Attach the terminal before authentication starts so the sidebar can reopen
# a waiting or failed login even if the provider exits before launching.
if ($env:HC_TERMINAL_ID) {
    try {
        & hc label $env:HC_TERMINAL_ID "herdr.profile=$environmentId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.engine.instance=$environmentId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.engine.provider=$agentFamily" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.profile.space=$SpaceId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.space=$SpaceId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.role=$Role" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.model.requested=$requestedModel" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.approval.mode=$approvalMode" | Out-Null
        if ($requestedEffort) { & hc label $env:HC_TERMINAL_ID "herdr.model.effort=$requestedEffort" | Out-Null }
    } catch {}
}
# Codex is isolated by CODEX_HOME alone. Keep the real user profile for it so
# the OAuth flow can open the user's current Chrome profile; with a redirected
# LOCALAPPDATA, Chrome would start a brand-new empty profile instead.
if ($agentFamily -ne "codex") {
    $env:USERPROFILE = $profileDir
    $env:HOME = $profileDir
    $env:APPDATA = $roamingDir
    $env:LOCALAPPDATA = $localDir
}

# Codex keeps its login, configuration, and sessions under CODEX_HOME. Pointing
# it at the new profile prevents both saved OAuth state and the background
# daemon from leaking into another tab. Inherited API keys are removed so the
# new environment always asks the person to choose its own account.
if ($agentFamily -eq "codex") {
    $codexHome = Join-Path $profileDir ".codex"
    New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
    $sharedSkillsHelper = Join-Path $PSScriptRoot "connect-shared-skills.ps1"
    if (Test-Path -LiteralPath $sharedSkillsHelper) { & $sharedSkillsHelper "codex" $codexHome | Out-Null }

    # Multi Agent Herdr may itself be started from Codex. Do not pass that
    # parent's CI/session markers into the child: they make a fresh Codex think
    # it is headless, suppress the normal ChatGPT login picker, and interfere
    # with Ctrl+C. Let Windows use its normal default browser instead.
    Get-ChildItem Env: | Where-Object {
        $_.Name -like "CODEX_*" -or $_.Name -in @("CI", "SSH_CONNECTION", "SSH_TTY", "BROWSER", "NO_BROWSER")
    } | ForEach-Object {
        Remove-Item -LiteralPath "Env:$($_.Name)" -ErrorAction SilentlyContinue
    }
    $env:TERM = "xterm-256color"
    $env:CODEX_HOME = $codexHome
    # Store the login in CODEX_HOME/auth.json, not the shared Windows Credential Manager.
    $codexConfig = Join-Path $codexHome "config.toml"
    if (-not (Test-Path -LiteralPath $codexConfig)) {
        Set-Content -LiteralPath $codexConfig -Value 'cli_auth_credentials_store = "file"' -Encoding ASCII
    }
    Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_API_KEY -ErrorAction SilentlyContinue
}

# Match OpenMausBot's account flow: every isolated CODEX_HOME signs in with a
# device code, then the normal interactive Codex session starts in that same home.
if ($agentFamily -eq "codex") {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & $resolvedCommand login status *> $null
    $codexStatusCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    $codexLoggedIn = $codexStatusCode -eq 0
    if (-not $codexLoggedIn) {
        Set-LoginState "waiting"
        try {
            Open-LoginPage "https://auth.openai.com/codex/device"
            $ErrorActionPreference = "Continue"
            & $resolvedCommand login --device-auth
            $codexLoginCode = $LASTEXITCODE
            $ErrorActionPreference = $previousErrorAction
            if ($codexLoginCode -ne 0) { throw "Codex sign-in did not complete." }
            $ErrorActionPreference = "SilentlyContinue"
            & $resolvedCommand login status *> $null
            $codexConfirmCode = $LASTEXITCODE
            $ErrorActionPreference = $previousErrorAction
            if ($codexConfirmCode -ne 0) { throw "Codex sign-in could not be confirmed." }
            Set-LoginState "authenticated"
        } catch {
            $ErrorActionPreference = $previousErrorAction
            Set-LoginState "failed" $_.Exception.Message
            throw
        }
    } else { Set-LoginState "authenticated" }
}

# Claude Code officially supports CLAUDE_CONFIG_DIR for relocating its user
# settings, account details, history, and plugins. A unique directory per tab
# keeps OAuth/keychain state separate instead of reusing the host login.
if ($agentFamily -eq "claude") {
    $claudeConfigDir = Join-Path $profileDir ".claude"
    New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    $sharedSkillsHelper = Join-Path $PSScriptRoot "connect-shared-skills.ps1"
    if (Test-Path -LiteralPath $sharedSkillsHelper) { & $sharedSkillsHelper "claude" $claudeConfigDir | Out-Null }
    $env:CLAUDE_CONFIG_DIR = $claudeConfigDir
    foreach ($name in @("CI", "BROWSER", "NO_BROWSER", "SSH_CONNECTION", "SSH_TTY")) {
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
}

if ($agentFamily -eq "claude") {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $claudeStatusRaw = (& $resolvedCommand auth status --json 2>$null | Out-String)
    $ErrorActionPreference = $previousErrorAction
    $claudeLoggedIn = $false
    try { $claudeLoggedIn = [bool](($claudeStatusRaw | ConvertFrom-Json).loggedIn) } catch {}
    if (-not $claudeLoggedIn) {
        Set-LoginState "waiting"
        try {
            $ErrorActionPreference = "Continue"
            & $resolvedCommand auth login
            $claudeLoginCode = $LASTEXITCODE
            $ErrorActionPreference = $previousErrorAction
            if ($claudeLoginCode -ne 0) { throw "Claude sign-in did not complete." }
            $ErrorActionPreference = "SilentlyContinue"
            $claudeStatusRaw = (& $resolvedCommand auth status --json 2>$null | Out-String)
            $ErrorActionPreference = $previousErrorAction
            try { $claudeLoggedIn = [bool](($claudeStatusRaw | ConvertFrom-Json).loggedIn) } catch { $claudeLoggedIn = $false }
            if (-not $claudeLoggedIn) { throw "Claude sign-in could not be confirmed." }
            Set-LoginState "authenticated"
        } catch {
            $ErrorActionPreference = $previousErrorAction
            Set-LoginState "failed" $_.Exception.Message
            throw
        }
    } else { Set-LoginState "authenticated" }
}

# Antigravity CLI stores OAuth in the Windows Credential Manager, which is
# shared by every process of the same Windows user and ignores HOME. Its own
# SSH-mode auth path intentionally bypasses that keyring and stores the token
# in ANTIGRAVITY_APP_DATA_DIR instead, giving every tab a genuinely separate
# login as well as separate conversation/session data.
if ($agentFamily -eq "antigravity") {
    $geminiDir = Join-Path $profileDir ".gemini"
    $antigravityDir = Join-Path $geminiDir "antigravity-cli"
    New-Item -ItemType Directory -Path $antigravityDir -Force | Out-Null
    $sharedSkillsHelper = Join-Path $PSScriptRoot "connect-shared-skills.ps1"
    if (Test-Path -LiteralPath $sharedSkillsHelper) { & $sharedSkillsHelper "antigravity" $geminiDir | Out-Null }
    $env:ANTIGRAVITY_GEMINI_DIR = $geminiDir
    $env:ANTIGRAVITY_APP_DATA_DIR = $antigravityDir
    $env:ANTIGRAVITY_EXECUTABLE_DATA_DIR = $antigravityDir
    $env:SSH_CONNECTION = "127.0.0.1 1 127.0.0.1 1"
    $env:SSH_TTY = "/dev/pts/0"
    $env:AGY_CLI_INTERACTIVE_HEADLESS = "true"

    $antigravityToken = Join-Path $antigravityDir "antigravity-oauth-token"
    if ((Test-Path -LiteralPath $antigravityToken) -and (Get-Item -LiteralPath $antigravityToken).Length -gt 16) {
        Set-LoginState "authenticated"
    } else {
        Set-LoginState "waiting"
    }
    $loginWatcher = Join-Path $PSScriptRoot "open-antigravity-login.ps1"
    if ($env:HC_TERMINAL_ID -and -not (Test-Path -LiteralPath $antigravityToken) -and (Test-Path -LiteralPath $loginWatcher)) {
        Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
            "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $loginWatcher,
            "-TerminalId", $env:HC_TERMINAL_ID
        ) | Out-Null
    }
}

Write-Host "New isolated agent environment: $environmentId" -ForegroundColor DarkGray
Write-Host "Space is unchanged; this tab has its own profile and session data." -ForegroundColor DarkGray

if ($env:HC_TERMINAL_ID) {
    try {
        & hc label $env:HC_TERMINAL_ID "herdr.profile=$environmentId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.engine.instance=$environmentId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.engine.provider=$agentFamily" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.profile.space=$SpaceId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.space=$SpaceId" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.role=$Role" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.model.requested=$requestedModel" | Out-Null
        & hc label $env:HC_TERMINAL_ID "herdr.approval.mode=$approvalMode" | Out-Null
        if ($requestedEffort) { & hc label $env:HC_TERMINAL_ID "herdr.model.effort=$requestedEffort" | Out-Null }
    } catch {}
}

$agentExitCode = 1
$returnToLogin = $false
try {
    Set-RuntimeState "starting"
    & $resolvedCommand @AgentArguments
    $agentExitCode = $LASTEXITCODE
} finally {
    # A provider logout removes its credential while the Herdr terminal stays
    # alive. Detect that state before restoring the host environment so this
    # same terminal can return to the provider's login flow instead of leaving
    # the user at an unrelated PowerShell prompt.
    if ($agentFamily -eq "codex") {
        # `codex login status` only checks that credentials exist. A revoked
        # refresh token therefore passes the earlier check, then the TUI exits
        # during account/read and leaves the person at a PowerShell prompt.
        # Read only this terminal's recent output, recognise that exact auth
        # failure, and logout while CODEX_HOME still points at this isolated
        # profile. The normal return-to-login path below will then restart the
        # same profile and open device authentication again.
        $terminalOutput = ""
        if ($env:HC_TERMINAL_ID -and $agentExitCode -ne 0) {
            try { $terminalOutput = (& hc read $env:HC_TERMINAL_ID --lines 120 | Out-String) } catch {}
        }
        $revokedCredential = $terminalOutput -match '(?i)(refresh token was revoked|access token could not be refreshed|account/read failed.*-32603)'
        if ($revokedCredential) {
            # Keep this message ASCII because this script is launched by
            # Windows PowerShell 5, which may parse UTF-8-without-BOM as ANSI.
            Write-Host "Codex session expired. Signing out this isolated profile and reopening login..." -ForegroundColor Yellow
            try {
                $previousErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "SilentlyContinue"
                & $resolvedCommand logout *> $null
                $ErrorActionPreference = $previousErrorAction
            } catch { $ErrorActionPreference = $previousErrorAction }
            $returnToLogin = $true
        } else {
            $auth = Read-JsonFile (Join-Path $profileDir ".codex\auth.json")
            $returnToLogin = -not [bool]($auth.tokens.access_token -or $auth.access_token)
        }
    } elseif ($agentFamily -eq "claude") {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $statusRaw = (& $resolvedCommand auth status --json 2>$null | Out-String)
        $ErrorActionPreference = $previousErrorAction
        try { $returnToLogin = -not [bool](($statusRaw | ConvertFrom-Json).loggedIn) } catch { $returnToLogin = $true }
    } elseif ($agentFamily -eq "antigravity") {
        $token = Join-Path $profileDir ".gemini\antigravity-cli\antigravity-oauth-token"
        $returnToLogin = -not ((Test-Path -LiteralPath $token) -and (Get-Item -LiteralPath $token).Length -gt 16)
    }
    if ($returnToLogin) { Set-LoginState "waiting"; Set-RuntimeState "waiting-login" }
    elseif ($agentExitCode -eq 0) { Set-RuntimeState "needs-restart" }
    else { Set-RuntimeState "error" "Agent exited with code $agentExitCode." }
    if ($profileLockPath -and (Test-Path -LiteralPath $profileLockPath)) {
        $ownedLock = Read-JsonFile $profileLockPath
        $ownedBoot = if ($ownedLock.bootUtc) { ([datetime]$ownedLock.bootUtc).ToUniversalTime() } else { [datetime]::MinValue }
        if ([int]$ownedLock.pid -eq $PID -and $ownedBoot -eq $currentBoot) {
            Remove-Item -LiteralPath $profileLockPath -Force -ErrorAction SilentlyContinue
        }
    }
    $env:USERPROFILE = $hostProfile
    $env:HOME = $hostHome
    $env:APPDATA = $hostAppData
    $env:LOCALAPPDATA = $hostLocalAppData
    Remove-Item Env:NAUAGENCY_AGENT_ENVIRONMENT_ID -ErrorAction SilentlyContinue
    Remove-Item Env:NAUAGENCY_ENGINE_INSTANCE_ID -ErrorAction SilentlyContinue
    Remove-Item Env:NAUAGENCY_HOST_PROFILE -ErrorAction SilentlyContinue
    Remove-Item Env:NAUAGENCY_AGENT_ENVIRONMENT_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:NAUAGENCY_APPROVAL_MODE -ErrorAction SilentlyContinue
    if ($agentFamily -eq "codex") {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    }
    if ($agentFamily -eq "claude") {
        Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    }
    if ($agentFamily -eq "antigravity") {
        Remove-Item Env:ANTIGRAVITY_GEMINI_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:ANTIGRAVITY_APP_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:ANTIGRAVITY_EXECUTABLE_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_CONNECTION -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_TTY -ErrorAction SilentlyContinue
        Remove-Item Env:AGY_CLI_INTERACTIVE_HEADLESS -ErrorAction SilentlyContinue
    }
}

if ($returnToLogin) {
    Write-Host "Account signed out. Returning this $agentFamily terminal to its login screen..." -ForegroundColor Yellow
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
        $AgentKey $SpaceId $Role $environmentId $resolvedCommand @AgentArguments
    exit $LASTEXITCODE
}
exit $agentExitCode
