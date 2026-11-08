# Script PowerShell chạy với quyền Administrator trên Windows
# 1. Cài đặt OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Khởi động và đặt tự động chạy
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 3. Mở firewall cổng 22
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

Write-Host "OpenSSH Server da duoc bat thanh cong!" -ForegroundColor Green
