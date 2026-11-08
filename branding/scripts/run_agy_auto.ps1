# ==============================================================================
# Script: launch_agent.ps1 / run_agy_auto.ps1
# Multi Agent Herdr - Tu dong phan bo moi truong co lap cho Antigravity CLI
# ==============================================================================

$rawArgs = @($args)
$forwardArgs = @()
$explicitAccount = $null

# 1. Phan tich tham so truyen vao
$i = 0
while ($i -lt $rawArgs.Count) {
    $arg = $rawArgs[$i]
    if ($arg -eq "-a" -or $arg -eq "--account") {
        $i++
        if ($i -lt $rawArgs.Count) {
            $explicitAccount = $rawArgs[$i]
        }
    } else {
        $forwardArgs += $arg
    }
    $i++
}

# 2. Tim file thuc thi agy.exe
$agyExe = "C:\Users\damna\AppData\Local\agy\bin\agy.exe"
if (-not (Test-Path $agyExe)) {
    $cmd = Get-Command "agy.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $agyExe = $cmd.Source }
}

# Neu chi kiem tra phien ban hoac help thi chay thang khong chiem slot
$isInfo = $false
foreach ($a in $forwardArgs) {
    if ($a -match '^(--version|-v|--help|-h|help)$') {
        $isInfo = $true
        break
    }
}
if ($isInfo) {
    if ($forwardArgs.Count -gt 0) { & $agyExe @forwardArgs } else { & $agyExe }
    exit $LASTEXITCODE
}

# 3. Xac dinh slot tai khoan (acc1, acc2, acc3...)
$baseDir = "C:\Users\damna\.antigravity-accounts"
if (-not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
}

$slot = $null
if ($explicitAccount -match '^\d+$') {
    $slot = [int]$explicitAccount
} elseif ($env:AGY_ACCOUNT -match '^\d+$') {
    $slot = [int]$env:AGY_ACCOUNT
} else {
    for ($idx = 1; $idx -le 50; $idx++) {
        $slotPath = Join-Path $baseDir "acc$idx"
        $pidFile = Join-Path $slotPath "session.pid"
        if (-not (Test-Path $slotPath)) {
            $slot = $idx
            break
        }
        if (Test-Path $pidFile) {
            $prevPid = (Get-Content $pidFile -ErrorAction SilentlyContinue).Trim()
            if ($prevPid -match '^\d+$') {
                $proc = Get-Process -Id ([int]$prevPid) -ErrorAction SilentlyContinue
                if ($proc -and ($proc.ProcessName -match "agy|powershell|cmd")) {
                    continue
                }
            }
        }
        $slot = $idx
        break
    }
}

if ($null -eq $slot) { $slot = 1 }

$slotDir = Join-Path $baseDir "acc$slot"
$pidFile = Join-Path $slotDir "session.pid"
$geminiDir = Join-Path $slotDir ".gemini"
$appDataDir = Join-Path $slotDir "AppData\Roaming"

if (-not (Test-Path $slotDir)) { New-Item -ItemType Directory -Path $slotDir -Force | Out-Null }
if (-not (Test-Path $geminiDir)) { New-Item -ItemType Directory -Path $geminiDir -Force | Out-Null }
if (-not (Test-Path $appDataDir)) { New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null }

$globalGemini = "C:\Users\damna\.gemini\GEMINI.md"
if (Test-Path $globalGemini) {
    Copy-Item $globalGemini (Join-Path $slotDir "GEMINI.md") -Force -ErrorAction SilentlyContinue
    Copy-Item $globalGemini (Join-Path $geminiDir "GEMINI.md") -Force -ErrorAction SilentlyContinue
}

# 4. Ghi PID de giu cho
Set-Content -Path $pidFile -Value $PID -Force

# 5. Tieu de terminal & tab Herdr (CHAY TRUOC KHI DOI BIEN USERPROFILE)
$title = "Antigravity $slot"
try {
    $host.UI.RawUI.WindowTitle = "$title (acc$slot)"
    [Console]::Write([char]27 + "]0;" + $title + [char]7)
} catch {}

$herdrExe = "$env:LOCALAPPDATA\Programs\herdr-app\herdr-app.exe"
if (Test-Path $herdrExe) {
    Start-Process -FilePath $herdrExe -ArgumentList "do", "tab.rename", "--name", "`"$title`"" -NoNewWindow -ErrorAction SilentlyContinue
}

# 6. Thiet lap moi truong cach ly
$env:USERPROFILE = $slotDir
$env:HOME = $slotDir
$env:APPDATA = $appDataDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   MULTI AGENT HERDR - ANTIGRAVITY (TAI KHOAN $slot)   " -ForegroundColor Yellow
Write-Host "   Moi truong cach ly: acc$slot                            " -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 7. Khoi chay Antigravity CLI
try {
    if ($forwardArgs.Count -gt 0) {
        & $agyExe @forwardArgs
    } else {
        & $agyExe
    }
} finally {
    if (Test-Path $pidFile) {
        $curr = (Get-Content $pidFile -ErrorAction SilentlyContinue).Trim()
        if ($curr -eq "$PID") {
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
}

exit $LASTEXITCODE
