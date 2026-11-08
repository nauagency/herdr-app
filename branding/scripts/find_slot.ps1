# ==============================================================================
# Script: find_slot.ps1
# Multi Agent Herdr - Tim slot trong va chuan bi moi truong
# ==============================================================================

$rawArgs = @($args)
$explicitAccount = $null

$i = 0
while ($i -lt $rawArgs.Count) {
    $arg = $rawArgs[$i]
    if ($arg -eq "-a" -or $arg -eq "--account") {
        $i++
        if ($i -lt $rawArgs.Count) { $explicitAccount = $rawArgs[$i] }
    }
    $i++
}

$baseDir = "C:\Users\damna\.antigravity-accounts"
if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }

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

# Doi ten tab Herdr (chay voi USERPROFILE goc cua may)
$herdrExe = "$env:LOCALAPPDATA\Programs\herdr-app\herdr-app.exe"
if (Test-Path $herdrExe) {
    Start-Process -FilePath $herdrExe -ArgumentList "do", "tab.rename", "--name", "`"Antigravity $slot`"" -NoNewWindow -ErrorAction SilentlyContinue
}

# Tra ve duy nhat so slot cho file cmd su dung
Write-Output $slot
