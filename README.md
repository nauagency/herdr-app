# Multi Agent Herdr - Herdr & Multi-Account Antigravity Setup (v0.1.13)

Hệ thống quản lý và vận hành song song 6 tài khoản Antigravity (Google Gemini) độc lập trên macOS và Windows PC thông qua Herdr & Antigravity CLI (`agy`), tích hợp cơ chế Zero-Bloat tiết kiệm >90% token cùng nhận diện thương hiệu Nauagency.

> **Dành cho Agent (AGY / AI Assistant):** Đọc file `CONVERSATION_CONTEXT.md` để nắm toàn bộ ngữ cảnh đã thảo luận và tiếp tục công việc từ bước kết nối.

---

## ⚡ Cài đặt nhanh 1-Click (1-Click Installers)

### 🍎 Dành cho macOS
Mở Terminal tại thư mục này và chạy lệnh:
```bash
./cai_dat_multi_agent_mac.sh
```
Trình cài đặt macOS sẽ tự động:
1. Kiểm tra và cài đặt/nâng cấp Herdr CLI (v0.9.5) & Herdr Desktop App (**v0.1.13**) mới nhất.
2. Tự động thiết lập ứng dụng `/Applications/Multi Agent.app` với bộ icon Retina Nauagency chuẩn macOS (`multi_agent_logo.icns`).
3. Đăng ký nhận diện LaunchServices và ký chứng thực ad-hoc để ứng dụng xuất hiện đẹp mắt trong Spotlight và Launchpad.
4. Cài đặt giao diện thương hiệu Nauagency (`branding/install_branding.sh`) vào Herdr GUI.
5. Tạo lệnh khởi động nhanh qua Terminal: `multi-agent`.
6. Thiết lập 6 tài khoản độc lập (`agy-1` đến `agy-6`) trong `~/.antigravity-accounts`.
7. Tự động tích hợp quy tắc tiết kiệm >90% token `GEMINI.md` vào từng tài khoản.
8. Cài đặt và kích hoạt plugin dán ảnh màn hình `herdr-paste-image` (`Cmd + V`).

---

### 🪟 Dành cho Windows
> **Bên Windows chỉ cần tải repo về và click đúp vào file `cai_dat_multi_agent_windows.bat` là xong toàn bộ từ A đến Z!**

Bộ cài 1-click sẽ tự động:
1. Kiểm tra và cài đặt ứng dụng Herdr bản mới nhất nếu máy chưa có.
2. Thiết lập 6 tài khoản độc lập (`agy-1` đến `agy-6`) trong `%USERPROFILE%\.antigravity-accounts`.
3. Tự động tích hợp quy tắc tiết kiệm >90% token `GEMINI.md` vào từng tài khoản.
4. Cài đặt giao diện nhận diện Nauagency cho Herdr Desktop.
5. Cài đặt plugin dán ảnh màn hình `herdr-paste-image` (`Ctrl + V`).
6. Tạo Shortcut **Multi Agent Herdr** với icon Nauagency chuẩn đa độ phân giải (`multi_agent_logo.ico`) ngay trên màn hình Desktop.
7. Tạo file **`Start-MultiAgent.bat`** để click đúp là mở Multi Agent Herdr ngay lập tức.

---

## 1. Cấu trúc kho lưu trữ
- `cai_dat_multi_agent_mac.sh`: Trình cài đặt 1-click tự động toàn diện cho macOS (v0.1.13).
- `setup_accounts_mac.sh`: Script cấu hình tài khoản macOS (tự động chuyển tiếp đến `cai_dat_multi_agent_mac.sh`).
- `cai_dat_multi_agent_windows.bat`: Trình cài đặt 1-click tự động cho Windows (chỉ cần click đúp).
- `Install-MultiAgent.ps1`: Script PowerShell tự động hóa toàn bộ việc cài đặt Herdr, 6 tài khoản, plugin và shortcut trên Windows.
- `Start-MultiAgent.bat`: Phím tắt khởi động nhanh Multi Agent Herdr trên Windows.
- `setup_pc_windows.ps1`: Script PowerShell bật OpenSSH Server trên Windows.
- `setup_accounts_windows.ps1`: Script cấu hình tài khoản Windows (tự động chuyển tiếp đến `Install-MultiAgent.ps1`).
- `assets/multi_agent_logo.icns`: Icon macOS Retina chuẩn đa kích thước từ 16x16 đến 1024x1024.
- `assets/multi_agent_logo.ico`: Icon Windows chuẩn đa kích thước (16x16, 32x32, 48x48, 64x64, 128x128, 256x256).
- `assets/multi_agent_logo.jpg`: Logo thương hiệu gốc Nauagency.
- `branding/`: Giao diện nhận diện thương hiệu Nauagency cho Herdr (layout `nauagency`, theme Warm Ink & Bronze, mod `nauagency-brand`, script cài đặt).
- `HUONG_DAN_CAI_DAT_PC.md`: Hướng dẫn chi tiết thiết lập máy tính PC Windows làm server SSH + Tailscale.
- `CONVERSATION_CONTEXT.md`: Tóm tắt toàn bộ ngữ cảnh trao đổi và mô hình kỹ thuật.
- `GEMINI.md`: Quy tắc Orchestrator Zero-Bloat tiết kiệm token.
- `web-hub/`: Giao diện Web Control Hub & Mobile PWA.

---

## 2. Cách tiếp tục công việc trên thiết bị khác
Khi mở agent `agy` trên máy khác, chỉ cần đưa lệnh:
```text
Đọc file CONVERSATION_CONTEXT.md và README.md trong repo này để hiểu bối cảnh và hướng dẫn tôi tiếp tục các bước thiết lập.
```

---

## 3. Quy tắc tiết kiệm token (Zero-Bloat Rule)
File `GEMINI.md` chứa quy tắc:
- **Luồng chính (Main Thread):** Đóng vai trò Orchestrator (Kiến trúc sư), không đọc log dài, không viết code dài trực tiếp.
- **Ủy thác việc nặng/nhẹ sang Subagent Flash (`Model: flash`):** Xử lý ngầm toàn bộ code, build, test.
- **Báo cáo tinh gọn:** Chỉ trả về kết quả cô đọng, giữ cho Context Window của luồng chính luôn siêu nhẹ.
- Tự động áp dụng cho cả 6 tài khoản Antigravity khi chạy trong Herdr.

---

## 4. Ứng dụng Desktop: Multi Agent Herdr
- **macOS:** Ứng dụng **Multi Agent** (`/Applications/Multi Agent.app`), icon Retina Nauagency, lệnh mở nhanh qua Terminal: `multi-agent`.
- **Windows:** Shortcut **Multi Agent Herdr** trên Desktop trỏ trực tiếp đến Herdr kèm icon Nauagency chuẩn `.ico`. Khởi động nhanh bằng `Start-MultiAgent.bat`.
- Biểu tượng thương hiệu: Thiết kế độc quyền theo nhận diện Nauagency (Warm Ink `#171311` & Terracotta Bronze `#b98c73`).

---

## 5. Web Control Hub & Mobile PWA
- Tên miền chính thức: **`https://multiagent.nauagency.asia`**
- Giao thức: Cloudflare Tunnel (Miễn phí 100%, bảo mật HTTPS tự động).
- Hướng dẫn cài App lên điện thoại:
  1. Mở Safari (iPhone) hoặc Chrome (Android) truy cập: `https://multiagent.nauagency.asia`.
  2. Bấm nút **Chia sẻ** (Share) ➔ Chọn **Thêm vào Màn hình chính** (Add to Home Screen).
  3. Biểu tượng **Multi Agent Herdr** với Logo Nauagency sẽ xuất hiện trên màn hình điện thoại để điều khiển dàn Agent từ xa.

---

## 6. Hướng dẫn sử dụng
1. **Khởi động ứng dụng:**
   - **macOS:** Mở `Multi Agent.app` trong Applications / Spotlight, hoặc gõ `multi-agent` trong Terminal.
   - **Windows:** Click đúp biểu tượng `Multi Agent Herdr` ngoài Desktop hoặc click đúp file `Start-MultiAgent.bat`.
2. **Chạy các tài khoản Agent:**
   - Trong cửa sổ terminal của Herdr, bạn có thể mở các tab riêng và gõ `agy-1`, `agy-2`, ..., `agy-6`.
   - Mỗi lệnh tương ứng với một tài khoản Google Gemini độc lập hoàn toàn, không lo rate-limit!
3. **Dán ảnh màn hình:**
   - Chụp ảnh màn hình (hoặc bấm `Cmd + Shift + 4` trên Mac / `Win + Shift + S` trên Windows), sau đó dán vào cửa sổ Herdr, plugin `herdr-paste-image` sẽ tự động dán đường dẫn ảnh vào cửa sổ agent để AI đọc trực tiếp.

---

## 7. Giao diện thương hiệu Nauagency (Branding)
Bộ cấu hình tùy biến giao diện nhận diện thương hiệu độc quyền cho Herdr Desktop bằng layout, theme và mod (không can thiệp binary, không đụng thư mục `frame/` bị Herdr ghi đè mỗi lần khởi động):

### 7.1. Cách cài đặt
- **Windows:** Chạy PowerShell:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\branding\install_branding.ps1
  ```
- **macOS:** Chạy Terminal:
  ```bash
  bash ./branding/install_branding.sh
  ```
Script tự động sao lưu cấu hình cũ trước khi ghi đè, kích hoạt layout `nauagency` làm mặc định và gửi tín hiệu chuyển đổi tức thì nếu ứng dụng Herdr đang mở.

### 7.2. Các thành phần đã tùy biến
- **Thanh tiêu đề (Sidebar Header):** Hiển thị logo Nauagency + tên "Multi Agent Herdr" cùng phụ đề "Nauagency" bằng Terracotta Bronze, giữ nguyên đầy đủ nút tìm kiếm nhanh và nút thu gọn/mở rộng sidebar.
- **Thanh trạng thái (Status Bar):** Tích hợp logo Nauagency và tên thương hiệu "Multi Agent Herdr" ở góc trái thanh trạng thái.
- **Bảng màu giao diện (Theme `nauagency`):** Chuẩn nhận diện Nauagency với màu nền Warm Ink (`#171311`) và màu nhấn Terracotta Bronze (`#b98c73`), áp dụng đồng bộ cho terminals, sidebar, tabs, cards, focus borders và scrollbars.

### 7.3. Các thành phần giữ nguyên chữ Herdr
- **Màn hình Welcome (Welcome Dialog):** Nằm trong thư mục `frame/welcome` vốn được ứng dụng Herdr ghi đè lại mỗi khi khởi động nên không can thiệp bằng cấu hình (sẽ tự đóng/ẩn sau khi hoàn tất thiết lập ban đầu).
- **Tên cửa sổ / Tên tiến trình hệ điều hành (Window Title / Process Name):** Được biên dịch cố định từ mã nguồn Rust/GPUI của ứng dụng (cần build lại từ source code nếu muốn đổi).
