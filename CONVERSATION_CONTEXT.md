# Tóm tắt ngữ cảnh cuộc hội thoại (Conversation Context)

## Mục tiêu của User
1. User muốn chạy đồng thời **6 tài khoản Antigravity** để không bị giới hạn token/rate-limit.
2. User thường xuyên chụp ảnh màn hình từ Clipboard và dán trực tiếp (`Cmd + V` / `Ctrl + V`).
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
   - MacBook Air làm thiết bị điều khiển giao diện qua Multi Agent Herdr (Herdr).
4. **Trạng thái hiện tại (Phiên bản v0.1.13):**
   - **macOS:**
     - Ứng dụng Desktop: `/Applications/Multi Agent Herdr.app` (Herdr App v0.1.13 mới nhất) với icon Retina Nauagency (`multi_agent_logo.icns`).
     - CLI: Lệnh `multi-agent-herdr`, `multi-agent`, `herdr-app`, `herdr` (v0.9.5).
     - Bộ cài đặt 1-click: `cai_dat_multi_agent_mac.sh`.
     - 6 môi trường độc lập: `agy-1` đến `agy-6` nạp kèm quy tắc Zero-Bloat tiết kiệm >90% token.
     - Plugin dán ảnh clipboard: `herdr-paste-image` kích hoạt sẵn.
     - Tailscale: Đã cài đặt và đang chạy sẵn sàng trên Mac (v1.104.5).
   - **Windows:**
     - Bộ cài 1-click: `cai_dat_multi_agent_windows.bat` (chạy `Install-MultiAgent.ps1`).
     - Shortcut Desktop: `Multi Agent Herdr` với icon chuẩn đa độ phân giải `multi_agent_logo.ico`.
     - Khởi động nhanh: `Start-MultiAgent.bat`.
     - Hướng dẫn cấu hình SSH Server & Tailscale: `HUONG_DAN_CAI_DAT_PC.md`.
   - **Web Hub & Mobile PWA:**
     - Địa chỉ: `https://multiagent.nauagency.asia`.
