[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateNotNullOrEmpty()][string]$AgentKey,
    [Parameter(Mandatory, Position = 1)][ValidateNotNullOrEmpty()][string]$AgentCommand,
    [Parameter(Position = 2, ValueFromRemainingArguments)][string[]]$AgentArguments = @()
)

$ErrorActionPreference = "Stop"
$commandInfo = Get-Command -Name $AgentCommand -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
$resolvedCommand = if ($commandInfo.Path) { $commandInfo.Path } else { $commandInfo.Source }

$hostProfile = $env:USERPROFILE
$hostHome = $env:HOME
$hostAppData = $env:APPDATA
$hostLocalAppData = $env:LOCALAPPDATA
$environmentRoot = Join-Path $hostLocalAppData "Nauagency\Multi Agent Herdr\agent-environments"
$safeAgentKey = $AgentKey -replace '[^A-Za-z0-9._-]', '-'
$environmentId = "{0}-{1}-{2}" -f $safeAgentKey, (Get-Date -Format "yyyyMMdd-HHmmssfff"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$profileDir = Join-Path $environmentRoot $environmentId
$roamingDir = Join-Path $profileDir "AppData\Roaming"
$localDir = Join-Path $profileDir "AppData\Local"

foreach ($dir in @($profileDir, $roamingDir, $localDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$metadata = [ordered]@{ id = $environmentId; agent = $AgentKey; createdAt = (Get-Date).ToString("o"); command = $resolvedCommand }
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileDir "environment.json") -Encoding UTF8

$env:NAUAGENCY_AGENT_ENVIRONMENT_ID = $environmentId
$env:NAUAGENCY_HOST_PROFILE = $hostProfile
# Codex is isolated by CODEX_HOME alone. Keep the real user profile for it so
# the OAuth flow can open the user's current Chrome profile; with a redirected
# LOCALAPPDATA, Chrome would start a brand-new empty profile instead.
if ($AgentKey -ne "codex") {
    $env:USERPROFILE = $profileDir
    $env:HOME = $profileDir
    $env:APPDATA = $roamingDir
    $env:LOCALAPPDATA = $localDir
}

# Codex keeps its login, configuration, and sessions under CODEX_HOME. Pointing
# it at the new profile prevents both saved OAuth state and the background
# daemon from leaking into another tab. Inherited API keys are removed so the
# new environment always asks the person to choose its own account.
if ($AgentKey -eq "codex") {
    $codexHome = Join-Path $profileDir ".codex"
    New-Item -ItemType Directory -Path $codexHome -Force | Out-Null

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
    Set-Content -LiteralPath (Join-Path $codexHome "config.toml") -Value 'cli_auth_credentials_store = "file"' -Encoding ASCII
    Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:CODEX_API_KEY -ErrorAction SilentlyContinue
}

# Claude Code officially supports CLAUDE_CONFIG_DIR for relocating its user
# settings, account details, history, and plugins. A unique directory per tab
# keeps OAuth/keychain state separate instead of reusing the host login.
if ($AgentKey -eq "claude") {
    $claudeConfigDir = Join-Path $profileDir ".claude"
    New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null
    $env:CLAUDE_CONFIG_DIR = $claudeConfigDir
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
}

# Antigravity CLI stores OAuth in the Windows Credential Manager, which is
# shared by every process of the same Windows user and ignores HOME. Its own
# SSH-mode auth path intentionally bypasses that keyring and stores the token
# in ANTIGRAVITY_APP_DATA_DIR instead, giving every tab a genuinely separate
# login as well as separate conversation/session data.
if ($AgentKey -eq "antigravity") {
    $geminiDir = Join-Path $profileDir ".gemini"
    $antigravityDir = Join-Path $geminiDir "antigravity-cli"
    New-Item -ItemType Directory -Path $antigravityDir -Force | Out-Null
    $env:ANTIGRAVITY_GEMINI_DIR = $geminiDir
    $env:ANTIGRAVITY_APP_DATA_DIR = $antigravityDir
    $env:ANTIGRAVITY_EXECUTABLE_DATA_DIR = $antigravityDir
    $env:SSH_CONNECTION = "127.0.0.1 1 127.0.0.1 1"
    $env:SSH_TTY = "/dev/pts/0"
    $env:AGY_CLI_INTERACTIVE_HEADLESS = "true"
}

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
    if ($AgentKey -eq "codex") {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    }
    if ($AgentKey -eq "claude") {
        Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
    }
    if ($AgentKey -eq "antigravity") {
        Remove-Item Env:ANTIGRAVITY_GEMINI_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:ANTIGRAVITY_APP_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:ANTIGRAVITY_EXECUTABLE_DATA_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_CONNECTION -ErrorAction SilentlyContinue
        Remove-Item Env:SSH_TTY -ErrorAction SilentlyContinue
        Remove-Item Env:AGY_CLI_INTERACTIVE_HEADLESS -ErrorAction SilentlyContinue
    }
}
exit $agentExitCode
