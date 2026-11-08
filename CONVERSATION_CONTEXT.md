# Tóm tắt ngữ cảnh cuộc hội thoại (Conversation Context)

## Mục tiêu của User
1. User muốn chạy đồng thời **6 tài khoản Antigravity** để không bị giới hạn token/rate-limit.
2. User thường xuyên chụp ảnh màn hình từ Clipboard và dán trực tiếp (`Cmd + V`).
3. Máy tính của User: **MacBook Air chip Apple M2 với 8GB RAM**.
4. User có thêm **1 máy PC Windows ở nhà**.

## Tiến trình & Phân tích đã thực hiện
1. **Lý do không mở được nhiều profile Antigravity GUI thông thường:**
   - Antigravity lưu token đăng nhập vào **macOS Keychain** cấp hệ điều hành (service `gemini`, account `antigravity`).
   - Mọi cửa sổ mở trên cùng 1 user Mac đều dùng chung 1 Keychain này, nên đăng xuất 1 app sẽ làm văng các app khác.
2. **So sánh các giải pháp:**
   - Đã phân tích: Swarmterm, OpenRig, Orca, HERDR.
   - **HERDR** được chọn vì: Lõi viết bằng Rust siêu nhẹ (phù hợp máy 8GB RAM), có app GUI (`herdr-app`), có plugin dán ảnh clipboard (`herdr-paste-image`), và hỗ trợ kết nối máy từ xa (Remote Machine via SSH).
3. **Mô hình triển khai tối ưu:**
   - PC Windows ở nhà (nhiều RAM) làm máy chủ cày ngầm các agent 24/7 (kết nối qua Tailscale + SSH).
   - MacBook Air làm thiết bị điều khiển giao diện qua Herdr.
4. **Trạng thái hiện tại:**
   - Đã cài đặt trên MacBook: `herdr`, `herdr-app`, `herdr-core` (hc), plugin `herdr-paste-image`.
   - Đã tạo sẵn 6 lệnh môi trường độc lập: `agy-1` đến `agy-6`.
   - Đang chuẩn bị thiết lập SSH và Tailscale trên PC Windows để kết nối vào Herdr.
