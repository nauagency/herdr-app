# Multi Agent - Herdr & Multi-Account Antigravity Setup

Hệ thống quản lý và vận hành song song 6 tài khoản Antigravity (Google Gemini) độc lập trên macOS và Windows PC thông qua Herdr & Antigravity CLI (`agy`), tích hợp cơ chế Zero-Bloat tiết kiệm >90% token.

> **Dành cho Agent (AGY / AI Assistant):** Đọc file `CONVERSATION_CONTEXT.md` để nắm toàn bộ ngữ cảnh đã thảo luận và tiếp tục công việc từ bước kết nối.

---

## 🚀 Cài đặt nhanh 1-Click trên Windows
> **Bên Windows chỉ cần tải repo về và click đúp vào file `cai_dat_multi_agent_windows.bat` là xong toàn bộ từ A đến Z!**

Bộ cài 1-click sẽ tự động:
1. Tự động kiểm tra và cài đặt ứng dụng Herdr bản mới nhất nếu máy chưa có.
2. Thiết lập 6 tài khoản độc lập (`agy-1` đến `agy-6`) trong `%USERPROFILE%\.antigravity-accounts`.
3. Tự động tích hợp quy tắc tiết kiệm >90% token `GEMINI.md` vào từng tài khoản.
4. Cài đặt plugin dán ảnh màn hình `herdr-paste-image`.
5. Tạo Shortcut **Multi Agent** với icon chính thức đẹp mắt ngay trên màn hình Desktop.
6. Tạo file **`Start-MultiAgent.bat`** để click đúp là mở Multi Agent ngay lập tức.

---

## 1. Cấu trúc kho lưu trữ
- `cai_dat_multi_agent_windows.bat`: Trình cài đặt 1-click tự động cho Windows (chỉ cần click đúp).
- `Install-MultiAgent.ps1`: Script PowerShell tự động hóa toàn bộ việc cài đặt Herdr, 6 tài khoản, plugin và shortcut trên Windows.
- `Start-MultiAgent.bat`: Phím tắt khởi động nhanh Multi Agent trên Windows.
- `setup_pc_windows.ps1`: Script PowerShell bật OpenSSH Server trên Windows.
- `setup_accounts_windows.ps1`: Script cấu hình tài khoản Windows (tự động chuyển tiếp đến `Install-MultiAgent.ps1`).
- `setup_accounts_mac.sh`: Script tự động tạo 6 môi trường CLI độc lập (`agy-1` đến `agy-6`) trên macOS.
- `assets/multi_agent_logo.ico`: Icon Windows chuẩn đa kích thước (16x16, 32x32, 48x48, 64x64, 128x128, 256x256).
- `assets/multi_agent_logo.jpg`: Logo thương hiệu gốc Nauagency.
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

## 3. Quy tắc tiết kiệm >90% Token (Zero-Bloat Rule)
File `GEMINI.md` chứa quy tắc:
- **Luồng chính (Main Thread):** Đóng vai trò Orchestrator (Kiến trúc sư), không đọc log dài, không viết code dài trực tiếp.
- **Ủy thác việc nặng/nhẹ sang Subagent Flash (`Model: flash`):** Xử lý ngầm toàn bộ code, build, test.
- **Báo cáo tinh gọn:** Chỉ trả về kết quả cô đọng, giữ cho Context Window của luồng chính luôn siêu nhẹ.
- Tự động áp dụng cho cả 6 tài khoản Antigravity khi chạy trong Herdr.

---

## 4. Ứng dụng Desktop: Multi Agent
- **macOS:** Ứng dụng **Multi Agent** (`/Applications/Multi Agent.app`), lệnh mở nhanh qua Terminal: `multi-agent`.
- **Windows:** Shortcut **Multi Agent** trên Desktop trỏ trực tiếp đến Herdr kèm icon Nauagency chuẩn `.ico`. Khởi động nhanh bằng `Start-MultiAgent.bat`.
- Biểu tượng thương hiệu: Thiết kế độc quyền theo nhận diện Nauagency (Warm Ink `#171311` & Terracotta Bronze `#b98c73`).

---

## 5. Web Control Hub & Mobile PWA
- Tên miền chính thức: **`https://multiagent.nauagency.asia`**
- Giao thức: Cloudflare Tunnel (Miễn phí 100%, bảo mật HTTPS tự động).
- Hướng dẫn cài App lên điện thoại:
  1. Mở Safari (iPhone) hoặc Chrome (Android) truy cập: `https://multiagent.nauagency.asia`.
  2. Bấm nút **Chia sẻ** (Share) ➔ Chọn **Thêm vào Màn hình chính** (Add to Home Screen).
  3. Biểu tượng **Multi Agent** với Logo Nauagency sẽ xuất hiện trên màn hình điện thoại để điều khiển dàn Agent từ xa.

---

## 6. Hướng dẫn sử dụng trên Windows
1. **Cài đặt 1-Click:** Tải repo về, click đúp vào file `cai_dat_multi_agent_windows.bat`.
2. **Khởi động ứng dụng:**
   - Click đúp vào biểu tượng **Multi Agent** ngoài Desktop.
   - Hoặc click đúp file `Start-MultiAgent.bat`.
3. **Chạy các tài khoản Agent:**
   - Trong cửa sổ terminal của Herdr, bạn có thể mở các tab riêng và gõ `agy-1`, `agy-2`, ..., `agy-6`.
   - Mỗi lệnh tương ứng với một tài khoản Google Gemini độc lập hoàn toàn, không lo rate-limit!
4. **Dán ảnh màn hình:**
   - Chụp ảnh màn hình (hoặc bấm `PrtScn` / `Win + Shift + S`), sau đó bấm phím tắt dán ảnh trong Herdr, plugin `herdr-paste-image` sẽ tự động dán đường dẫn ảnh vào cửa sổ agent để AI đọc trực tiếp.
