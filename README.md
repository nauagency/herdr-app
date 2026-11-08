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
- Tên ứng dụng: **Multi Agent** (`/Applications/Multi Agent.app`)
- Biểu tượng thương hiệu: Thiết kế độc quyền theo nhận diện Nauagency (Warm Ink `#171311` & Terracotta Bronze `#b98c73`).
- Lệnh khởi động nhanh qua Terminal: `multi-agent`
