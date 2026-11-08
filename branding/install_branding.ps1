<#
.SYNOPSIS
    Cài đặt giao diện thương hiệu Nauagency / Multi Agent Herdr cho Herdr trên Windows.
.DESCRIPTION
    - Sao lưu các file cấu hình cũ trước khi ghi đè.
    - Cài đặt layout: layouts\nauagency.json, layouts\nauagency.svg
    - Cài đặt theme: themes\nauagency.json (Warm Ink #171311 & Terracotta Bronze #b98c73)
    - Cài đặt mod thương hiệu: mods\nauagency-brand\ (logo + tên thương hiệu)
    - Đặt layout 'nauagency' làm mặc định qua shared.json (theo tài liệu Herdr: shared("layout"))
    - Áp dụng ngay nếu Herdr đang chạy qua lệnh 'herdr-app do layout.switch'.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$herdrSource = Join-Path $scriptDir "herdr-app"
$configDir = Join-Path $env:USERPROFILE ".config\herdr-app"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   CAI DAT GIAO DIEN MULTI AGENT HERDR / NAUAGENCY CHO HERDR   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $herdrSource)) {
    throw "Khong tim thay thu muc nguon: $herdrSource"
}

# 1. Đảm bảo các thư mục cấu hình tồn tại
$layoutsDir = Join-Path $configDir "layouts"
$themesDir = Join-Path $configDir "themes"
$modsDir = Join-Path $configDir "mods"
$backupsDir = Join-Path $configDir "backups"

foreach ($dir in @($layoutsDir, $themesDir, $modsDir, $backupsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# 2. Sao lưu các file cũ trước khi ghi đè
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$currentBackupDir = Join-Path $backupsDir "branding_$timestamp"
$hasBackup = $false

$itemsToBackup = @(
    (Join-Path $layoutsDir "nauagency.json"),
    (Join-Path $layoutsDir "nauagency.svg"),
    (Join-Path $themesDir "nauagency.json"),
    (Join-Path $modsDir "nauagency-brand"),
    (Join-Path $configDir "shared.json")
)

foreach ($item in $itemsToBackup) {
    if (Test-Path $item) {
        if (-not $hasBackup) {
            New-Item -ItemType Directory -Path $currentBackupDir -Force | Out-Null
            $hasBackup = $true
        }
        $relPath = $item.Substring($configDir.Length).TrimStart('\', '/')
        $destBackup = Join-Path $currentBackupDir $relPath
        $destBackupParent = Split-Path $destBackup -Parent
        if (-not (Test-Path $destBackupParent)) {
            New-Item -ItemType Directory -Path $destBackupParent -Force | Out-Null
        }
        Copy-Item -Path $item -Destination $destBackup -Recurse -Force
        Write-Host "[+] Da sao luu: $relPath -> backups\branding_$timestamp\$relPath" -ForegroundColor Gray
    }
}

if (-not $hasBackup) {
    Write-Host "[i] Chua co ban cai dat nao truoc do can sao luu." -ForegroundColor Gray
}

# 3. Copy các file branding vào .config\herdr-app
Write-Host "`n[+] Dang sao chep layout, theme va mod..." -ForegroundColor Yellow

# Layouts
Copy-Item -Path (Join-Path $herdrSource "layouts\nauagency.json") -Destination (Join-Path $layoutsDir "nauagency.json") -Force
Copy-Item -Path (Join-Path $herdrSource "layouts\nauagency.svg") -Destination (Join-Path $layoutsDir "nauagency.svg") -Force
Write-Host "  -> layouts\nauagency.json va nauagency.svg" -ForegroundColor Green

# Themes
Copy-Item -Path (Join-Path $herdrSource "themes\nauagency.json") -Destination (Join-Path $themesDir "nauagency.json") -Force
Write-Host "  -> themes\nauagency.json" -ForegroundColor Green

# Mods
$destModDir = Join-Path $modsDir "nauagency-brand"
if (Test-Path $destModDir) {
    Remove-Item -Path $destModDir -Recurse -Force
}
Copy-Item -Path (Join-Path $herdrSource "mods\nauagency-brand") -Destination $destModDir -Recurse -Force
Write-Host "  -> mods\nauagency-brand\" -ForegroundColor Green

# 4. Thiết lập layout 'nauagency' làm mặc định trong shared.json
# QUAN TRỌNG: phải đóng Herdr trước khi ghi, vì app đang chạy sẽ ghi đè lại shared.json (về layout 'main').
$wasRunning = $false
if (Get-Process "herdr-app" -ErrorAction SilentlyContinue) {
    $wasRunning = $true
    Get-Process "herdr-app" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}
# Theo tài liệu Herdr (AGENTS.md): layout hien tai/mac dinh duoc luu tai shared("layout") trong shared.json
$sharedJsonPath = Join-Path $configDir "shared.json"
$sharedObj = $null
if (Test-Path $sharedJsonPath) {
    try {
        $content = Get-Content -Path $sharedJsonPath -Raw -Encoding UTF8
        if ($content.Trim()) {
            $sharedObj = $content | ConvertFrom-Json
        }
    } catch {
        Write-Warning "Khong the doc shared.json hien tai: $_"
    }
}

if ($null -eq $sharedObj) {
    $sharedObj = [PSCustomObject]@{
        layout = "nauagency"
        "frame.welcomed" = "finished"
    }
} else {
    if ($sharedObj.PSObject.Properties['layout']) {
        $sharedObj.layout = "nauagency"
    } else {
        $sharedObj | Add-Member -NotePropertyName "layout" -NotePropertyValue "nauagency"
    }
    if ($sharedObj.PSObject.Properties['frame.welcomed']) {
        $sharedObj."frame.welcomed" = "finished"
    } else {
        $sharedObj | Add-Member -NotePropertyName "frame.welcomed" -NotePropertyValue "finished"
    }
}

$newJson = $sharedObj | ConvertTo-Json -Compress
Set-Content -Path $sharedJsonPath -Value $newJson -Encoding UTF8
Write-Host "`n[+] Da dat layout 'nauagency' lam mac dinh trong shared.json" -ForegroundColor Green

# 5. Kiểm tra mod bằng herdr-app check và chuyển layout trực tiếp nếu app đang chạy
$herdrExe = Join-Path $env:LOCALAPPDATA "Programs\herdr-app\herdr-app.exe"
if (-not (Test-Path $herdrExe)) {
    $cmd = Get-Command "herdr-app" -ErrorAction SilentlyContinue
    if ($cmd) {
        $herdrExe = $cmd.Source
    }
}

if (Test-Path $herdrExe) {
    Write-Host "`n[+] Kiem tra mod nauagency-brand bang 'herdr-app check'..." -ForegroundColor Yellow
    $checkProc = Start-Process -FilePath $herdrExe -ArgumentList "check", "$destModDir" -NoNewWindow -PassThru -Wait
    if ($checkProc.ExitCode -eq 0) {
        Write-Host "  -> Mod check PASSED hop le!" -ForegroundColor Green
    } else {
        Write-Warning "  -> Mod check bao loi (ma thoat: $($checkProc.ExitCode))"
    }

    # Nếu herdr-app đang chạy, chuyển layout ngay lập tức
    $runningApp = Get-Process "herdr-app" -ErrorAction SilentlyContinue
    if ($runningApp) {
        Write-Host "[+] Phat hien Herdr dang chay, dang chuyen layout sang 'nauagency'..." -ForegroundColor Yellow
        Start-Process -FilePath $herdrExe -ArgumentList "do", "layout.switch", "--name", "nauagency" -NoNewWindow -Wait
        Write-Host "  -> Da gui lenh layout.switch thanh cong!" -ForegroundColor Green
    }
}

# Mở lại Herdr nếu trước đó đang chạy (đã đóng ở bước 4 để shared.json không bị ghi đè)
if ($wasRunning -and (Test-Path $herdrExe)) {
    Start-Process -FilePath $herdrExe
    Write-Host "[+] Da mo lai Herdr voi giao dien Nauagency." -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "   DA CAI DAT THANH CONG BRANDING MULTI AGENT HERDR / NAUAGENCY " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
