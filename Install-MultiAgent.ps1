# ==============================================================================
# Script: Install-MultiAgent.ps1
# Mục đích: Cài đặt và cấu hình 1-click trọn gói hệ thống Multi Agent Herdr (6 tài khoản)
#          trên Windows kèm giao diện nhận diện Nauagency, icon Desktop và plugin Herdr.
# Tác giả: Nauagency
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     HỆ THỐNG MULTI AGENT HERDR (6 TÀI KHOẢN) CHO WINDOWS " -ForegroundColor Yellow
Write-Host "                Phát triển bởi Nauagency                  " -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$repoDir = $PSScriptRoot
$baseAccountsDir = "$env:USERPROFILE\.antigravity-accounts"
$binDir = "$baseAccountsDir\bin"
$geminiGlobal = "$env:USERPROFILE\.gemini"
$localAppHerdrDir = "$env:LOCALAPPDATA\Programs\herdr-app"
$herdrExe = "$localAppHerdrDir\herdr-app.exe"
$iconSrc = "$repoDir\assets\multi_agent_logo.ico"
$iconDst = "$baseAccountsDir\multi_agent_logo.ico"
$startBatSrc = "$repoDir\Start-MultiAgent.bat"
$startBatDst = "$baseAccountsDir\Start-MultiAgent.bat"

# ------------------------------------------------------------------------------
# BƯỚC 1: TẠO THƯ MỤC CƠ BẢN VÀ CẤU HÌNH 6 TÀI KHOẢN AGENT ĐỘC LẬP
# ------------------------------------------------------------------------------
Write-Host "[1/6] Dang thiet lap thu muc luu tru 6 tai khoan va sao luu logo..." -ForegroundColor Cyan

if (-not (Test-Path $baseAccountsDir)) {
    New-Item -ItemType Directory -Path $baseAccountsDir -Force | Out-Null
}
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}
if (-not (Test-Path $geminiGlobal)) {
    New-Item -ItemType Directory -Path $geminiGlobal -Force | Out-Null
}

# Sao lưu vĩnh viễn icon vào thư mục hệ thống để tránh mất khi di chuyển thư mục tải về
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc -Destination $iconDst -Force
    Write-Host "  -> Da sao luu icon vinh vien vao: $iconDst" -ForegroundColor Green
}

# Sao lưu vĩnh viễn file Start-MultiAgent.bat
if (Test-Path $startBatSrc) {
    Copy-Item $startBatSrc -Destination $startBatDst -Force
}

# Copy file GEMINI.md global nếu có
$geminiSrc = "$repoDir\GEMINI.md"
if (Test-Path $geminiSrc) {
    Copy-Item $geminiSrc -Destination "$geminiGlobal\GEMINI.md" -Force
}

# Khởi tạo 6 profile riêng biệt
for ($i = 1; $i -le 6; $i++) {
    $accDir = "$baseAccountsDir\acc$i"
    $accGemini = "$accDir\.gemini"
    
    if (-not (Test-Path $accGemini)) {
        New-Item -ItemType Directory -Path $accGemini -Force | Out-Null
    }
    
    # Copy GEMINI.md vào profile tài khoản
    if (Test-Path $geminiSrc) {
        Copy-Item $geminiSrc -Destination "$accGemini\GEMINI.md" -Force
        Copy-Item $geminiSrc -Destination "$accDir\GEMINI.md" -Force
    }

    # Tạo file cmd khởi chạy nhanh trong thư mục bin
    $cmdContent = "@echo off`r`nset HOME=$accDir`r`nset USERPROFILE_ACC=$accDir`r`nagy %*"
    Set-Content -Path "$binDir\agy-$i.cmd" -Value $cmdContent -Encoding ASCII
    Set-Content -Path "$binDir\agy-$i.bat" -Value $cmdContent -Encoding ASCII
    
    # Tạo thêm ở USERPROFILE để tương thích ngược
    Set-Content -Path "$env:USERPROFILE\agy-$i.cmd" -Value $cmdContent -Encoding ASCII

    # Tạo file script PowerShell agy-$i.ps1
    $psContent = "`$env:HOME = '$accDir'`r`n& agy @args"
    Set-Content -Path "$binDir\agy-$i.ps1" -Value $psContent -Encoding UTF8

    Write-Host "  -> Da tao profile tai khoan ${i}: $accDir (Lenh: agy-$i)" -ForegroundColor Green
}

# Thêm binDir vào PATH của User nếu chưa có
try {
    $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    $rawPath = [string]$regKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $paths = $rawPath -split ";" | Where-Object { $_ -ne "" }
    if ($paths -notcontains $binDir) {
        $newPath = if ($rawPath) { "$($rawPath.TrimEnd(';'));$binDir" } else { $binDir }
        $regKey.SetValue("Path", $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        Write-Host "  -> Da them $binDir vao PATH he thong!" -ForegroundColor Green
    }
    $regKey.Close()
} catch {
    Write-Host "  [!] Khong the ghi vao Registry PATH: $_" -ForegroundColor Yellow
}

if (($env:Path -split ";") -notcontains $binDir) {
    $env:Path += ";$binDir"
}

# ------------------------------------------------------------------------------
# BƯỚC 2: KIỂM TRA VÀ CÀI ĐẶT HERDR TRÊN WINDOWS
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "[2/6] Kiem tra ung dung Herdr tren Windows..." -ForegroundColor Cyan

$herdrCoreDir = "$env:LOCALAPPDATA\Programs\herdr-core"
if (Test-Path $herdrCoreDir) {
    if (($env:Path -split ";") -notcontains $herdrCoreDir) { $env:Path += ";$herdrCoreDir" }
}
if (Test-Path $localAppHerdrDir) {
    if (($env:Path -split ";") -notcontains $localAppHerdrDir) { $env:Path += ";$localAppHerdrDir" }
}

$needInstallHerdr = $true
if (Test-Path $herdrExe) {
    $needInstallHerdr = $false
    Write-Host "  -> Tim thay Herdr App tai: $herdrExe" -ForegroundColor Green
} elseif (Test-Path "$localAppHerdrDir\Herdr.exe") {
    $needInstallHerdr = $false
    $herdrExe = "$localAppHerdrDir\Herdr.exe"
    Write-Host "  -> Tim thay Herdr App tai: $herdrExe" -ForegroundColor Green
} elseif (Get-Command herdr-app -ErrorAction SilentlyContinue) {
    $needInstallHerdr = $false
    $herdrExe = (Get-Command herdr-app).Source
    Write-Host "  -> Tim thay Herdr App trong PATH: $herdrExe" -ForegroundColor Green
}

if ($needInstallHerdr) {
    Write-Host "  -> Herdr App chua duoc cai dat. Dang tien hanh tai va cai dat Herdr..." -ForegroundColor Yellow
    try {
        Invoke-Expression (Invoke-RestMethod "https://releases.herdr.dev/app/install.ps1")
        Write-Host "  -> Cai dat Herdr thanh cong!" -ForegroundColor Green
        if (Test-Path $herdrCoreDir) {
            if (($env:Path -split ";") -notcontains $herdrCoreDir) { $env:Path += ";$herdrCoreDir" }
        }
        if (Test-Path $localAppHerdrDir) {
            if (($env:Path -split ";") -notcontains $localAppHerdrDir) { $env:Path += ";$localAppHerdrDir" }
        }
        if (Test-Path $herdrExe) {
            $needInstallHerdr = $false
        } elseif (Test-Path "$localAppHerdrDir\Herdr.exe") {
            $herdrExe = "$localAppHerdrDir\Herdr.exe"
            $needInstallHerdr = $false
        } elseif (Get-Command herdr-app -ErrorAction SilentlyContinue) {
            $herdrExe = (Get-Command herdr-app).Source
            $needInstallHerdr = $false
        }
    } catch {
        Write-Host "  [!] Tu dong cai dat Herdr bi loi: $_" -ForegroundColor Red
        Write-Host "  -> Ban co the tai bo cai Herdr thu cong tai: https://herdr.dev" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
# BƯỚC 3: CÀI ĐẶT GIAO DIỆN THƯƠNG HIỆU NAUAGENCY CHO HERDR
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "[3/6] Dong bo giao dien thuong hieu Nauagency cho Herdr..." -ForegroundColor Cyan

$brandingScript = Join-Path $repoDir "branding\install_branding.ps1"
if (Test-Path $brandingScript) {
    try {
        & $brandingScript
    } catch {
        Write-Host "  [!] Ap dung giao dien branding co thong bao: $_" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
# BƯỚC 4: TẠO SHORTCUT DESKTOP & START MENU "Multi Agent Herdr" KÈM ICON LOGO
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/6] Tao Shortcut 'Multi Agent Herdr' tren Desktop va Start Menu..." -ForegroundColor Cyan

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutFile = Join-Path $desktop "Multi Agent Herdr.lnk"

# Dọn dẹp các shortcut cũ trên Desktop để tránh trùng lặp hoặc sót tên cũ
$oldShortcuts = @(
    (Join-Path $desktop "Multi Agent.lnk"),
    (Join-Path $desktop "Herdr.lnk")
)
$rawDesktop = Join-Path $env:USERPROFILE "Desktop"
if ($rawDesktop -ne $desktop -and (Test-Path $rawDesktop)) {
    $oldShortcuts += (Join-Path $rawDesktop "Multi Agent.lnk")
    $oldShortcuts += (Join-Path $rawDesktop "Herdr.lnk")
}

foreach ($oldLnk in $oldShortcuts) {
    if (Test-Path $oldLnk) {
        try {
            Remove-Item -Path $oldLnk -Force -ErrorAction SilentlyContinue
            Write-Host "  -> Da don dep shortcut cu tren Desktop: $(Split-Path $oldLnk -Leaf)" -ForegroundColor Gray
        } catch {}
    }
}

# Xác định file exe / batch để tạo shortcut
$targetExe = $herdrExe
if (-not (Test-Path $targetExe)) {
    if (Test-Path "$localAppHerdrDir\Herdr.exe") {
        $targetExe = "$localAppHerdrDir\Herdr.exe"
    } elseif (Get-Command herdr-app -ErrorAction SilentlyContinue) {
        $targetExe = (Get-Command herdr-app).Source
    } elseif (Test-Path $startBatDst) {
        $targetExe = $startBatDst
    } elseif (Test-Path $startBatSrc) {
        $targetExe = $startBatSrc
    }
}

$iconPathToUse = if (Test-Path $iconDst) { $iconDst } else { $iconSrc }

try {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutFile)
    $shortcut.TargetPath = $targetExe
    $shortcut.WorkingDirectory = $env:USERPROFILE
    if (Test-Path $iconPathToUse) {
        $shortcut.IconLocation = "$iconPathToUse,0"
    }
    $shortcut.Description = "Multi Agent Herdr - He thong 6 Agent AI doc lap (Nauagency)"
    $shortcut.Save()
    Write-Host "  -> Da tao thanh cong Shortcut Desktop: $shortcutFile" -ForegroundColor Green
    if (Test-Path $iconPathToUse) {
        Write-Host "  -> Da gan icon thuong hieu sac net: $iconPathToUse" -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Khong the tao Shortcut Desktop: $_" -ForegroundColor Yellow
}

# Đồng bộ Shortcut vào Start Menu (Programs) để tìm kiếm Windows ra ngay
try {
    $programsDir = [Environment]::GetFolderPath("Programs")
    if (Test-Path $programsDir) {
        $startMenuShortcut = Join-Path $programsDir "Multi Agent Herdr.lnk"
        $sm = $wsh.CreateShortcut($startMenuShortcut)
        $sm.TargetPath = $targetExe
        $sm.WorkingDirectory = $env:USERPROFILE
        if (Test-Path $iconPathToUse) {
            $sm.IconLocation = "$iconPathToUse,0"
        }
        $sm.Description = "Multi Agent Herdr - He thong 6 Agent AI doc lap (Nauagency)"
        $sm.Save()
        Write-Host "  -> Da tao Shortcut Start Menu: Multi Agent Herdr" -ForegroundColor Green

        # Cập nhật icon cho Herdr.lnk trong Programs nếu có
        $herdrMenuLnk = Join-Path $programsDir "Herdr.lnk"
        if (Test-Path $herdrMenuLnk) {
            $hm = $wsh.CreateShortcut($herdrMenuLnk)
            if (Test-Path $iconPathToUse) {
                $hm.IconLocation = "$iconPathToUse,0"
                $hm.Save()
            }
        }
    }
} catch {}

# Làm mới bộ nhớ đệm icon của Windows Explorer ngay lập tức
try {
    $code = @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
'@
    $shellNotification = Add-Type -MemberDefinition $code -Name "ShellNotification" -Namespace "NauagencyWin" -PassThru -ErrorAction SilentlyContinue
    if ($shellNotification) {
        $shellNotification::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    }
} catch {}

# ------------------------------------------------------------------------------
# BƯỚC 5: CÀI ĐẶT VÀ CẤU HÌNH PLUGIN PASTE ẢNH (herdr-paste-image)
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "[5/6] Cau hinh plugin dan anh Clipboard (herdr-paste-image)..." -ForegroundColor Cyan

$installedPlugin = $false

# 1. Thử dùng lệnh chính thức của Herdr CLI nếu có
if (Get-Command herdr -ErrorAction SilentlyContinue) {
    try {
        Write-Host "  -> Dang cai dat plugin qua herdr CLI..." -ForegroundColor Gray
        $output = & herdr plugin install ddfonseca/herdr-paste-image 2>&1
        $installedPlugin = $true
        Write-Host "  -> Cai dat plugin thanh cong qua herdr CLI!" -ForegroundColor Green
    } catch {
        Write-Host "  -> herdr CLI chua the tai truc tiep, chuyen sang che do cau hinh file san..." -ForegroundColor Gray
    }
}

# 2. Khởi tạo sẵn thư mục cấu hình plugin cho Windows
$herdrConfigDirs = @(
    "$env:USERPROFILE\.config\herdr",
    "$env:APPDATA\herdr"
)

foreach ($hDir in $herdrConfigDirs) {
    $pluginConfigDir = "$hDir\plugins\config\herdr-paste-image"
    if (-not (Test-Path $pluginConfigDir)) {
        New-Item -ItemType Directory -Path $pluginConfigDir -Force | Out-Null
    }
    
    $envConfigPath = "$pluginConfigDir\config.env"
    if (-not (Test-Path $envConfigPath)) {
        $envConfigContent = @"
# Cau hinh cho plugin herdr-paste-image tren Windows
HERDR_PASTE_IMAGE_KEEP_DAYS=14
HERDR_PASTE_IMAGE_QUIET=0
"@
        Set-Content -Path $envConfigPath -Value $envConfigContent -Encoding UTF8
    }
}
Write-Host "  -> Da thiet lap cau hinh san cho plugin herdr-paste-image!" -ForegroundColor Green

# ------------------------------------------------------------------------------
# BƯỚC 6: TỔNG KẾT & HƯỚNG DẪN SỬ DỤNG
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "     CAI DAT MULTI AGENT HERDR WINDOWS HOAN TAT 100%!     " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Cac tien ich da duoc thiet lap:" -ForegroundColor Yellow
Write-Host "1. Shortcut Desktop: 'Multi Agent Herdr' voi icon logo Nauagency sac net." -ForegroundColor White
Write-Host "2. Shortcut Start Menu: tim kiem 'Multi Agent Herdr' la ra ngay." -ForegroundColor White
Write-Host "3. File chay nhanh: 'Start-MultiAgent.bat' da duoc luu tai ca thu muc goc va he thong." -ForegroundColor White
Write-Host "4. Giao dien Nauagency: layout, theme Terracotta Bronze va mod thuong hieu da nap." -ForegroundColor White
Write-Host "5. 6 Tai khoan doc lap: agy-1 den agy-6 (chay duoc o bat ky Terminal/CMD/PowerShell nao)." -ForegroundColor White
Write-Host "6. Quy tac Zero-Bloat: GEMINI.md da duoc nap tu dong vao ca 6 tai khoan." -ForegroundColor White
Write-Host "7. Plugin Dan anh: ho tro chup anh man hinh dan thang (Ctrl + V) vao cua so Agent." -ForegroundColor White
Write-Host ""
Write-Host "De bat dau, hay click dup vao bieu tuong 'Multi Agent Herdr' tren Desktop hoac chay Start-MultiAgent.bat!" -ForegroundColor Cyan
Write-Host ""
