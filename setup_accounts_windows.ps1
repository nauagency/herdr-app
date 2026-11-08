# Script tá»± Ä‘á»™ng cáº¥u hÃ¬nh 6 tÃ i khoáº£n Antigravity trÃªn Windows PowerShell
# Cháº¡y script nÃ y báº±ng PowerShell hoáº·c click Ä‘Ãºp cai_dat_multi_agent_windows.bat

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
    Set-Content -Path $cmdPath -Value "@echo off`r`nset "USERPROFILE=$accDir"`r`nset "HOME=$accDir"`r`nset "APPDATA=$accDir\AppData\Roaming"`r`nset "LOCALAPPDATA=$accDir\AppData\Local"`r`nagy %*"

    $binCmdPath = "$binDir\agy-$i.cmd"
    Set-Content -Path $binCmdPath -Value "@echo off`r`nset "USERPROFILE=$accDir"`r`nset "HOME=$accDir"`r`nset "APPDATA=$accDir\AppData\Roaming"`r`nset "LOCALAPPDATA=$accDir\AppData\Local"`r`nagy %*"
    
    Write-Host "Da tao tai khoan $i tai: $accDir (Lenh: agy-$i)" -ForegroundColor Green
}

# Sao lÆ°u icon vÄ©nh viá»…n vÃ  táº¡o shortcut Desktop Multi Agent Herdr náº¿u cÃ³ icon
$iconSrc = Join-Path $PSScriptRoot "assets\multi_agent_logo.ico"
$iconDst = Join-Path $baseDir "multi_agent_logo.ico"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc -Destination $iconDst -Force
}
$iconPathToUse = if (Test-Path $iconDst) { $iconDst } else { $iconSrc }

try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutLnk = Join-Path $desktopPath "Multi Agent Herdr.lnk"
    $oldLnk = Join-Path $desktopPath "Multi Agent.lnk"
    if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force -ErrorAction SilentlyContinue }

    $herdrExe = "$env:LOCALAPPDATA\Programs\herdr-app\herdr-app.exe"
    $target = if (Test-Path $herdrExe) { $herdrExe } else { "$env:LOCALAPPDATA\Programs\herdr-app\Herdr.exe" }
    
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutLnk)
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $env:USERPROFILE
    if (Test-Path $iconPathToUse) {
        $shortcut.IconLocation = "$iconPathToUse,0"
    }
    $shortcut.Description = "Multi Agent Herdr - He thong 6 Agent AI doc lap (Nauagency)"
    $shortcut.Save()
    Write-Host "Da tao shortcut 'Multi Agent Herdr' tren Desktop!" -ForegroundColor Green
} catch {}

Write-Host "`nThanh cong! Ban da co the mo Terminal va chay agy-1 den agy-6 tren Windows!" -ForegroundColor Yellow

