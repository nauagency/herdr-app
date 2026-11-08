# Zero-Bloat Main Thread: Cơ Chế Tiết Kiệm >90% Token (Orchestrator Pattern)

## 1. Nguyên lý tiết kiệm >90% Token ở Luồng Chính (Zero-Bloat Main Thread)
- Khi hoạt động ở luồng chat chính, mọi nội dung xuất hiện (đọc file dài, log terminal, viết code/script dài) sẽ bị tích lũy vào Context Window của model chính qua từng lượt chat.
- **Quy tắc nghiêm ngặt**: Model ở luồng chính KHÔNG trực tiếp đọc file dài, KHÔNG xả log terminal hoặc tự viết code/script dài. Luồng chính chỉ giữ vai trò **Kiến trúc sư & Điều phối viên (Orchestrator)**.

## 2. Đẩy 100% Việc Nặng/Nhẹ Sang Subagent Flash (`Model: "flash"`)
- **Tác vụ Nhẹ / Vừa / Đơn luồng:**
  - Lập tức gọi 1 Subagent (`invoke_subagent` với `TypeName: "self"`, `Model: "flash"`) để xử lý trọn gói từ khảo sát, đọc/ghi file, chạy lệnh đến kiểm tra kết quả.
- **Tác vụ Nặng / Đa hạng mục:**
  - Lập Master Plan ngắn gọn, chia thành 2 đến 4 nhánh công việc độc lập (tối đa 4 nhánh).
  - Kích hoạt đồng thời 2–4 Subagents (`TypeName: "self"`, `Model: "flash"`) chạy song song trong cùng một lượt.

## 3. Báo Cáo Ngược Tinh Gọn (Compact Return)
- Toàn bộ quá trình đọc hàng nghìn dòng code, bóc tách dữ liệu (Excel, AutoCAD...), chạy script và sửa lỗi đều diễn ra trong vùng nhớ riêng của Gemini Flash (tiêu thụ token Flash).
- Khi làm xong, Subagent `flash` chỉ gửi về cho luồng chính bản tóm tắt kết quả, số liệu đã xác thực và đường dẫn file thành phẩm, giữ cho bộ nhớ của luồng chính luôn siêu nhẹ suốt cả phiên làm việc.
