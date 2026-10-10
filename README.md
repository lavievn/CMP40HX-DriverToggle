# CMP40HX-DriverToggle
chuyển đổi trực tiếp giữa 2 driver cho 40hx
THIẾT LẬP CHO HAI DRIVER CỦA BẠN
- GPU công suất tối đa: tải driver bạn muốn sử dụng để làm việc, chạy AI (raincandy, dartraiden..), giải nén bằng win rar ra một thư mục tuỳ chọn, 
  INF dự kiến: Display.Driver\nvaci.inf

- GPU LOL / Valorant (driver 460 mod):
  tải driver bạn muốn sử dụng để chơi LOL, valorant (HIEUPC...), giải nén bằng win rar ra một thư mục tuỳ chọn
  INF dự kiến: Display.Driver\nvaei.inf

Trong giao diện: chọn 'Thiết lập driver' > dùng nút 'Chọn...'
cho hai THƯ MỤC ở trên > kiểm tra INF và DriverVer hiện ra > 'Lưu'.
Ô Model ép: để trống khi cả hai INF chứa DEV_1F0B.

CÁCH KIỂM TRA QUÉT INF - CHỈ ĐỌC, KHÔNG CẦN ADMIN / KHÔNG CÀI DRIVER
Mở PowerShell trong thư mục công cụ và dùng:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CMP30HX-DriverToggle.ps1 -ScanFolder '...\đường dẫn đến folder (FIX LOL) 40HX_NVIDIA_Setup'

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CMP30HX-DriverToggle.ps1 -ScanFolder '...\đường dẫn đến folder 617.14-desktop-win10-win11-64bit-international-dch-whql'

KẾT QUẢ ĐÚNG: 'OK: ...nvaei.inf' cho 460 mod,
'OK: ...nvaci.inf' cho 617.14. Phiên bản DriverVer sẽ
được đọc từ INF, không suy ra từ tên thư mục.

LƯU Ý AN TOÀN
- Quét INF tự động chỉ kiểm tra Class=Display, khai báo thiết bị
  DEV_1F0B trong section .NTamd64 và DriverVer. Nó KHÔNG thay thế
  xác minh tính tương thích/chữ ký/chất lượng driver trên GPU thật.
- Nếu có 0 hoặc trên 1 INF hợp lệ trong thư mục, chương trình DỪNG
  và yêu cầu chọn một thư mục rõ ràng hơn; không tự chọn bừa.
- Chuyển driver thật vẫn dùng API của công cụ gốc và vẫn có thể
  yêu cầu khởi động lại. Chưa kiểm thử trên máy CMP 40HX của bạn.
- Giữ nguyên các thư mục driver sau khi cấu hình; không đổi nội dung
  INF hoặc di chuyển bộ cài mà không thiết lập lại.
- Khi có sự cố, mở cmp30hx-switch.log và gửi thông báo lỗi.
