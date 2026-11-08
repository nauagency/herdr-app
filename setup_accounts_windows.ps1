# Script tự động cấu hình 6 tài khoản Antigravity trên Windows PowerShell
# Chạy script này bằng PowerShell

Write-Host "Dang thiet lap 6 tai khoan Antigravity tren Windows..." -ForegroundColor Cyan

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$baseDir = "$env:USERPROFILE\.antigravity-accounts"
$geminiGlobal = "$env:USERPROFILE\.gemini"
$geminiSrc = Join-Path $scriptDir "GEMINI.md"
$icoPath = Join-Path $scriptDir "assets\multi_agent_logo.ico"

if (-not (Test-Path $geminiGlobal)) {
    New-Item -ItemType Directory -Path $geminiGlobal -Force | Out-Null
}

# Sao chép GEMINI.md nếu có
if (Test-Path $geminiSrc) {
    Copy-Item $geminiSrc -Destination "$geminiGlobal\GEMINI.md" -Force
}

for ($i = 1; $i -le 6; $i++) {
    $accDir = "$baseDir\acc$i"
    $accGemini = "$accDir\.gemini"
    
    if (-not (Test-Path $accGemini)) {
        New-Item -ItemType Directory -Path $accGemini -Force | Out-Null
    }
    
    # Copy GEMINI.md vào từng profile
    if (Test-Path $geminiSrc) {
        Copy-Item $geminiSrc -Destination "$accGemini\GEMINI.md" -Force
    }

    # Tạo lệnh alias / script nhanh
    $cmdPath = "$env:USERPROFILE\agy-$i.cmd"
    Set-Content -Path $cmdPath -Value "@echo off`r`nset HOME=$accDir`r`nagy %*"
    
    Write-Host "Da tao tai khoan $i tai: $accDir (Lenh: agy-$i)" -ForegroundColor Green
}

# Cập nhật Shortcut Desktop: Đổi tên Herdr thành Multi Agent & gán Logo
Write-Host "`nKiem tra shortcut Herdr tren Desktop Windows..." -ForegroundColor Cyan
try {
    $desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
    $herdrLnk = Join-Path $desktopPath "Herdr.lnk"
    $multiAgentLnk = Join-Path $desktopPath "Multi Agent.lnk"
    $wsh = New-Object -ComObject WScript.Shell

    if (Test-Path $herdrLnk) {
        Move-Item -Path $herdrLnk -Destination $multiAgentLnk -Force
        $shortcut = $wsh.CreateShortcut($multiAgentLnk)
        if (Test-Path $icoPath) {
            $shortcut.IconLocation = "$icoPath,0"
        }
        $shortcut.Save()
        Write-Host "Da doi ten shortcut Desktop 'Herdr' thanh 'Multi Agent' va gan Logo thanh cong!" -ForegroundColor Green
    } elseif (Test-Path $multiAgentLnk) {
        $shortcut = $wsh.CreateShortcut($multiAgentLnk)
        if (Test-Path $icoPath) {
            $shortcut.IconLocation = "$icoPath,0"
            $shortcut.Save()
            Write-Host "Da cap nhat Logo Nauagency cho shortcut 'Multi Agent' tren Desktop!" -ForegroundColor Green
        }
    } else {
        Write-Host "Chua thay shortcut Herdr tren Desktop (Neu ban cai Herdr sau, chi can doi ten shortcut thanh 'Multi Agent' va gan icon assets\multi_agent_logo.ico)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Khong the tu dong cap nhat shortcut Desktop: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "`nThanh cong! Ban da co the mo Terminal va chay agy-1 den agy-6 tren Windows!" -ForegroundColor Yellow
