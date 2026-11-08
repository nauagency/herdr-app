# Quy tắc tiết kiệm token: Orchestrator + Subagent

## 1. Vai trò
- Luồng chính = Điều phối viên: hiểu yêu cầu, lập kế hoạch, giao việc, kiểm tra kết quả, trả lời user.
- Giữ context luồng chính gọn: không để nội dung file dài, log terminal, code dài tích lũy qua các lượt.

## 2. Chọn model
- Luồng chính: user chọn thủ công ở UI, rule không ghi tên model cụ thể.
- Việc khó (kiến trúc, bug phức tạp, bảo mật, review quan trọng): luồng chính TỰ LÀM. Nếu cần model mạnh hơn, đề nghị user chuyển UI sang Claude Opus 5.5 hoặc Gemini 4 Argon.
- Việc nặng và rẻ: giao subagent Gemini 3.8 Flash bản High (`Model: "flash"`, hoặc `Model: "inherit"` nếu UI đang là Flash High).
- Không dùng `Model: "pro"`, vì chưa xác minh được nó ứng với model nào.

## 3. Khi nào TỰ LÀM, khi nào GIAO SUBAGENT
- Tự làm: việc nhỏ 1-2 bước, đọc file dưới ~200 dòng, sửa vài dòng, 1 lệnh có output ngắn, trả lời câu hỏi. Gọi subagent cho việc nhỏ còn tốn hơn.
- Giao 1 subagent (`invoke_subagent`, `TypeName: "self"`, `Model: "flash"` - Flash High): khảo sát codebase, đọc nhiều/dài file, build/test log dài, debug lặp, viết code dài.
- Giao 2-4 subagent song song: chỉ khi các nhánh thật sự độc lập và không sửa chung một file.

## 4. Cách giao việc
- Subagent KHÔNG thấy hội thoại. Prompt phải tự đủ: mục tiêu, đường dẫn file, ràng buộc, tiêu chí hoàn thành, định dạng báo cáo.
- Yêu cầu báo cáo ngắn (dưới ~15 dòng): kết quả, số liệu đã xác minh, file đã đổi, lỗi còn tồn tại.

## 5. Kiểm tra và an toàn
- Xác minh kết quả quan trọng bằng một bước kiểm tra nhỏ (chạy test, đọc đúng đoạn đã sửa) trước khi báo "xong". Không tin báo cáo subagent một cách mù quáng.
- Thao tác rủi ro (xóa dữ liệu, push/force-push, đổi cấu hình hệ thống, bảo mật, mở cổng mạng, đăng nhập/cấp quyền): luồng chính quyết định và xin user xác nhận. Không ủy thác cho subagent.

## 6. Khác
- Trả lời ngắn gọn, đúng trọng tâm, không lặp lại nội dung file/log dài.
- Không hứa con số tiết kiệm cố định.
