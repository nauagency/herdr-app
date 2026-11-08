# Script tự động cấu hình 6 tài khoản Antigravity trên Windows PowerShell
# Chạy script này bằng PowerShell hoặc click đúp cai_dat_multi_agent_windows.bat

$installScript = Join-Path $PSScriptRoot "Install-MultiAgent.ps1"
if (Test-Path $installScript) {
    & $installScript
    exit $LASTEXITCODE
}

Write-Host "Dang thiet lap 6 tai khoan Antigravity tren Windows..." -ForegroundColor Cyan

$baseDir = "$env:USERPROFILE\.antigravity-accounts"
$binDir = "$baseDir\bin"
$geminiGlobal = "$env:USERPROFILE\.gemini"

if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
if (-not (Test-Path $geminiGlobal)) { New-Item -ItemType Directory -Path $geminiGlobal -Force | Out-Null }

if (Test-Path "GEMINI.md") {
    Copy-Item "GEMINI.md" -Destination "$geminiGlobal\GEMINI.md" -Force
}

for ($i = 1; $i -le 6; $i++) {
    $accDir = "$baseDir\acc$i"
    $accGemini = "$accDir\.gemini"
    
    if (-not (Test-Path $accGemini)) {
        New-Item -ItemType Directory -Path $accGemini -Force | Out-Null
    }
    
    if (Test-Path "GEMINI.md") {
        Copy-Item "GEMINI.md" -Destination "$accGemini\GEMINI.md" -Force
        Copy-Item "GEMINI.md" -Destination "$accDir\GEMINI.md" -Force
    }

    $cmdPath = "$env:USERPROFILE\agy-$i.cmd"
    Set-Content -Path $cmdPath -Value "@echo off`r`nset HOME=$accDir`r`nagy %*"

    $binCmdPath = "$binDir\agy-$i.cmd"
    Set-Content -Path $binCmdPath -Value "@echo off`r`nset HOME=$accDir`r`nagy %*"
    
    Write-Host "Da tao tai khoan $i tai: $accDir (Lenh: agy-$i)" -ForegroundColor Green
}

Write-Host "`nThanh cong! Ban da co the mo Terminal va chay agy-1 den agy-6 tren Windows!" -ForegroundColor Yellow
