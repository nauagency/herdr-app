# HƯỚNG DẪN THIẾT LẬP PC WINDOWS LÀM MÁY CHỦ CHẠY 6 TÀI KHOẢN AGENT

Tài liệu này lưu lại toàn bộ các bước thiết lập để bạn mở trên PC hoặc xem lại bất cứ lúc nào.

---

## BƯỚC 1: Chỉnh không cho PC Windows đi ngủ (Sleep)
1. Nhấn phím `Windows` ➔ Gõ tìm **Power & sleep settings**.
2. Thiết lập:
   - **Screen (Màn hình):** Tắt sau `5 phút` hoặc `10 phút` (Màn hình tự tắt đen để bảo vệ máy và tiết kiệm điện).
   - **Sleep (Chế độ ngủ của máy):** Chọn **Never (Không bao giờ)**.

---

## BƯỚC 2: Bật tính năng SSH trên Windows
1. Nhấn phím `Windows` ➔ Gõ tìm **PowerShell** ➔ Click chuột phải chọn **Run as administrator** (Chạy với quyền Quản trị viên).
2. Copy đoạn lệnh bên dưới dán vào PowerShell và bấm `Enter`:

```powershell
# 1. Cài đặt OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Bật dịch vụ OpenSSH và cho phép tự khởi động cùng Windows
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 3. Mở cổng tường lửa cho SSH
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

---

## BƯỚC 3: Cài đặt Tailscale (Kết nối an toàn Mac ➔ PC)
1. **Trên PC Windows:**
   - Vào trang: [https://tailscale.com/download/windows](https://tailscale.com/download/windows) tải và cài đặt.
   - Cài xong, click vào icon Tailscale ở góc phải taskbar ➔ Chọn **Log in** ➔ Đăng nhập bằng tài khoản Google.
2. **Trên MacBook:**
   - Mở App Store trên Mac tìm **Tailscale** tải về (hoặc chạy lệnh: `brew install --cask tailscale`).
   - Đăng nhập bằng **chính tài khoản Google** bạn đã đăng nhập trên PC.

---

## BƯỚC 4: Kết nối từ MacBook vào PC
1. Xem địa chỉ IP của PC trên Tailscale:
   - Click vào icon Tailscale trên PC Windows, bạn sẽ thấy địa chỉ IP dạng: `100.x.y.z` (Ví dụ: `100.85.120.45`).
2. Xem tên tài khoản Windows (Username):
   - Mở CMD trên Windows, gõ `whoami` sẽ thấy tên tài khoản của bạn.
3. Trên MacBook:
   - Mở **Herdr.app** ➔ Chọn **Add a machine** ➔ Điền IP `100.x.y.z` và Username của PC vào là kết nối thành công!
