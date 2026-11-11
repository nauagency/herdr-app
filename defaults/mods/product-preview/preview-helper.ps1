[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet("capture", "open")][string]$Action,
    [Parameter(Mandatory, Position = 1)][string]$Value,
    [Parameter(Position = 2)][string]$JobId = "preview"
)

$ErrorActionPreference = "Stop"
if ($Value -match '^https?://') {
    $uri = [Uri]$Value
    if ($uri.Host -notin @("localhost", "127.0.0.1", "::1")) { throw "Only localhost preview URLs are allowed." }
}

if ($Action -eq "open") {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Value
    $info.UseShellExecute = $true
    [Diagnostics.Process]::Start($info) | Out-Null
    exit 0
}

if ($Value -notmatch '^https?://') { throw "Capture requires a localhost URL." }
$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path ${env:ProgramFiles} "Microsoft\Edge\Application\msedge.exe")
)
$browser = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $browser) { throw "Chrome or Edge was not found." }

$cacheRoot = Join-Path $env:LOCALAPPDATA "Nauagency\Multi Agent Herdr\preview-cache"
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
$safeJob = $JobId -replace '[^A-Za-z0-9._-]', '-'
$stamp = Get-Date -Format "yyyyMMddHHmmssfff"
$output = Join-Path $cacheRoot "$safeJob-$stamp.png"
& $browser "--headless=new" "--disable-gpu" "--hide-scrollbars" "--window-size=1365,900" "--screenshot=$output" $Value 2>$null | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw "The local preview could not be captured." }

Get-ChildItem -LiteralPath $cacheRoot -Filter "$safeJob-*.png" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 3 |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
$output
