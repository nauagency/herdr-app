# HƯỚNG DẪN THIẾT LẬP MULTI AGENT TRÊN PC WINDOWS

> ⚡ **CÀI ĐẶT 1-CLICK TỰ ĐỘNG (KHUYÊN DÙNG):**  
> **Bên Windows chỉ cần tải repo về và click đúp vào file `cai_dat_multi_agent_windows.bat` là xong toàn bộ từ A đến Z!**

---

## 🌟 TÍNH NĂNG CỦA BỘ CÀI 1-CLICK WINDOWS

Khi bạn click đúp vào file **`cai_dat_multi_agent_windows.bat`**, hệ thống sẽ tự động thực hiện:

1. **Cài đặt Herdr:** Tự động kiểm tra và tải/cài đặt Herdr chính thức phiên bản mới nhất cho Windows nếu máy chưa có.
2. **Cấu hình 6 tài khoản độc lập:** Tự động tạo 6 môi trường riêng biệt (`agy-1` đến `agy-6`) tại `%USERPROFILE%\.antigravity-accounts\acc1..6`, không bao giờ bị đụng token hay đăng xuất lẫn nhau.
3. **Kích hoạt quy tắc Zero-Bloat:** Nạp quy tắc `GEMINI.md` vào cả 6 tài khoản để tiết kiệm >90% token ngữ cảnh qua mô hình Orchestrator & Subagent Flash.
4. **Tạo Shortcut Desktop "Multi Agent Herdr":** Tự động tạo biểu tượng ngoài màn hình Desktop với tên **Multi Agent Herdr** và icon logo Nauagency chuẩn Windows (`multi_agent_logo.ico`).
5. **Cài đặt Plugin Paste Ảnh:** Tự động cấu hình plugin `herdr-paste-image` giúp bạn chụp ảnh màn hình bằng Clipboard rồi dán trực tiếp vào Agent.
6. **Thêm lệnh vào PATH:** Có thể mở bất kỳ Terminal, CMD hoặc PowerShell nào gõ `agy-1` đến `agy-6` là chạy ngay.
7. **Khởi động nhanh:** Cung cấp sẵn file **`Start-MultiAgent.bat`** để click đúp là mở Multi Agent Herdr bất cứ khi nào.

---

## 🖥️ HƯỚNG DẪN DÙNG PC LÀM MÁY CHỦ CHẠY AGENT TỪ XA (KẾT NỐI TỪ MACBOOK)

Nếu bạn muốn biến chiếc PC Windows ở nhà thành máy chủ chạy Agent 24/7 và điều khiển từ MacBook, hãy làm thêm các bước đơn giản sau:

### BƯỚC 1: Chỉnh không cho PC Windows đi ngủ (Sleep)
1. Nhấn phím `Windows` ➔ Gõ tìm **Power & sleep settings**.
2. Thiết lập:
   - **Screen (Màn hình):** Tắt sau `5 phút` hoặc `10 phút` (Tự tắt màn hình để bảo vệ và tiết kiệm điện).
   - **Sleep (Chế độ ngủ):** Chọn **Never (Không bao giờ)**.

---

### BƯỚC 2: Bật tính năng OpenSSH trên Windows
1. Nhấn phím `Windows` ➔ Gõ tìm **PowerShell** ➔ Click chuột phải chọn **Run as administrator** (Chạy với quyền Quản trị viên).
2. Dán đoạn lệnh sau và bấm `Enter` (hoặc chạy script `setup_pc_windows.ps1`):

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

### BƯỚC 3: Cài đặt Tailscale (Mạng riêng ảo an toàn Mac ➔ PC)
1. **Trên PC Windows:**
   - Vào [https://tailscale.com/download/windows](https://tailscale.com/download/windows) tải và cài đặt.
   - Click vào icon Tailscale ở góc taskbar ➔ **Log in** ➔ Đăng nhập bằng tài khoản Google.
2. **Trên MacBook:**
   - Mở App Store tìm **Tailscale** tải về (hoặc chạy `brew install --cask tailscale`).
   - Đăng nhập bằng **chính tài khoản Google** đã dùng trên PC.

---

### BƯỚC 4: Kết nối từ MacBook sang PC Windows qua Multi Agent Herdr
1. **Lấy thông tin PC:**
   - Click icon Tailscale trên Windows để xem IP dạng: `100.x.y.z` (Ví dụ: `100.85.120.45`).
   - Mở CMD trên Windows, gõ `whoami` để xem tên tài khoản Windows (ví dụ: `hoangdam` hoặc `PC\hoangdam`).
2. **Thêm máy vào Multi Agent Herdr trên MacBook:**
   - Mở **Multi Agent Herdr** trên Mac ➔ Chọn **Add a machine** ➔ Điền IP `100.x.y.z` và Username của PC vào là hoàn tất!


