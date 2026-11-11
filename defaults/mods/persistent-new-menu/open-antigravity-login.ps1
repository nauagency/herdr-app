param(
    [Parameter(Mandatory = $true)]
    [string]$TerminalId
)

$ErrorActionPreference = "SilentlyContinue"
if ($env:HERDR_CORE_BIN -and (Test-Path -LiteralPath $env:HERDR_CORE_BIN -PathType Leaf)) {
    Set-Alias -Name hc -Value $env:HERDR_CORE_BIN -Scope Script
}
$deadline = [DateTime]::UtcNow.AddMinutes(5)

function Open-InChrome([string]$Url) {
    $chrome = Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $chrome) {
        $candidates = @(
            (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
            (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
        )
        $chrome = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if ($chrome) {
        Start-Process -FilePath $chrome -ArgumentList $Url | Out-Null
        return
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Url
    $startInfo.UseShellExecute = $true
    [Diagnostics.Process]::Start($startInfo) | Out-Null
}

while ([DateTime]::UtcNow -lt $deadline) {
    $screen = (& hc read $TerminalId 2>$null | Out-String)
    if ($screen -match "https://accounts\.google\.com/o/oauth2/auth\?") {
        $parts = [Collections.Generic.List[string]]::new()
        $collecting = $false
        foreach ($line in ($screen -split "`r?`n")) {
            $clean = ($line -replace "\x1B\[[0-?]*[ -/]*[@-~]", "").Trim()
            if (-not $collecting -and $clean.StartsWith("https://accounts.google.com/o/oauth2/auth?")) {
                $collecting = $true
            }
            if ($collecting) {
                if ($clean -match "^[A-Za-z0-9%+._~:/?&=-]+$") {
                    $parts.Add($clean)
                    continue
                }
                if ($parts.Count -gt 0) { break }
            }
        }

        $url = $parts -join ""
        $parsed = $null
        if ($url -match "[?&]state=[A-Za-z0-9._~-]+$" -and [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed)) {
            Open-InChrome $url
            exit 0
        }
    }
    Start-Sleep -Milliseconds 500
}

exit 0
