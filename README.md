# Herdr & Multi-Account Antigravity Setup

Tài liệu và script thiết lập môi trường chạy song song 6 tài khoản Antigravity (Google Gemini) trên máy Mac và PC thông qua Herdr & Antigravity CLI (`agy`).

> **Dành cho Agent (AGY / AI Assistant):** Đọc file `CONVERSATION_CONTEXT.md` để nắm toàn bộ ngữ cảnh đã thảo luận và tiếp tục công việc từ bước kết nối.

---

## 1. Cấu trúc kho lưu trữ
- `CONVERSATION_CONTEXT.md`: Tóm tắt toàn bộ ngữ cảnh trao đổi, lý do chọn Herdr và tiến độ hiện tại.
- `HUONG_DAN_CAI_DAT_PC.md`: Hướng dẫn chi tiết thiết lập máy tính PC Windows làm server SSH + Tailscale.
- `setup_pc_windows.ps1`: Script PowerShell 1-click kích hoạt OpenSSH Server trên Windows.
- `setup_accounts_mac.sh`: Script tự động tạo 6 môi trường CLI độc lập (`agy-1` đến `agy-6`) trên macOS.

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
- **Biểu tượng thương hiệu:** Thiết kế độc quyền theo nhận diện Nauagency (Warm Ink `#171311` & Terracotta Bronze `#b98c73`).
- **Trên macOS:**
  - Ứng dụng: `/Applications/Multi Agent.app`
  - Khởi động nhanh qua Spotlight hoặc Terminal: `multi-agent`
- **Trên Windows (Phân biệt quan trọng):**
  - Hệ điều hành Windows **KHÔNG có file `.app`** (vì `.app` là định dạng gói ứng dụng macOS).
  - Trên Windows, ứng dụng là file thực thi **`Herdr.exe`** và khi cài đặt sẽ tạo shortcut **Herdr** trên màn hình Desktop.
  - Người dùng Windows chỉ cần:
    1. Đổi tên shortcut Desktop từ **Herdr** ➔ **Multi Agent**.
    2. Click chuột phải ➔ **Properties** ➔ **Change Icon...** ➔ Trỏ đến file `assets/multi_agent_logo.ico` (hoặc `assets/multi_agent_logo.jpg`).
    3. Hoặc chạy script `setup_accounts_windows.ps1` để tự động hóa toàn bộ.

---

## 5. Web Control Hub & Mobile PWA
- Tên miền chính thức: **`https://multiagent.nauagency.asia`**
- Giao thức: Cloudflare Tunnel (Miễn phí 100%, bảo mật HTTPS tự động).
- Hướng dẫn cài App lên điện thoại:
  1. Mở Safari (iPhone) hoặc Chrome (Android) truy cập: `https://multiagent.nauagency.asia`.
  2. Bấm nút **Chia sẻ** (Share) ➔ Chọn **Thêm vào Màn hình chính** (Add to Home Screen).
  3. Biểu tượng **Multi Agent** với Logo Nauagency sẽ xuất hiện trên màn hình điện thoại, mở full screen để điều khiển dàn Agent từ xa.

---

## 6. Thiết lập Multi Agent trên Windows
1. Đọc hướng dẫn chi tiết từng bước tại: **`HUONG_DAN_CAI_DAT_PC.md`**.
2. Mở PowerShell trên Windows tại thư mục này và chạy lệnh:
   ```powershell
   .\setup_accounts_windows.ps1
   ```
3. Sau khi chạy:
   - Script tự động đổi tên shortcut Desktop thành **Multi Agent** và gán Logo Nauagency (`assets\multi_agent_logo.ico`).
   - Bạn có thể gõ ngay `agy-1`, `agy-2`... `agy-6` trên PowerShell hoặc terminal của Herdr để vận hành đồng thời 6 tài khoản không lo chạm trần rate limit!
