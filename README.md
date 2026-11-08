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
