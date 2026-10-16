Dựa theo bản gốc chạy trên 30HX của Lâm Đặng - https://www.facebook.com/lamdang99/
# CMP 40HX Driver Toggle

Công cụ Windows (PowerShell/WinForms) chuyển đổi giữa **hai gói driver NVIDIA CMP 40HX** đã được người dùng tự chuẩn bị. Chỉ hỗ trợ thiết bị có Hardware ID `PCI\VEN_10DE&DEV_1F0B`.

> **Cảnh báo:** Việc cài lại driver có thể làm gián đoạn GPU, gây màn hình đen hoặc yêu cầu khởi động lại. Không đảm bảo chuyển đổi không cần khởi động lại. Hãy sao lưu dữ liệu, tạo điểm khôi phục Windows và tự chịu trách nhiệm khi sử dụng.
> Có khả năng gây treo, drop driver trong quá trình sử dụng - không phải là cách nếu muốn dùng ổn định lâu dài - yêu cầu luôn giữ 2 bộ driver gốc để cài lại đầy đủ khi cần

## Tính năng

- Hai hồ sơ: **Làm việc/AI** và **Chơi game/LOL**.
- Chọn **thư mục driver**, công cụ tự tìm INF thuộc lớp `Display`, có khai báo cài đặt 64-bit cho `DEV_1F0B` và trường `DriverVer`.
- Nếu thư mục chứa nhiều INF phù hợp, công cụ từ chối chọn ngẫu nhiên.
- Giao diện WinForms, kiểm tra trạng thái và mô phỏng kiểm thử không thay đổi driver thật.
- Tạo shortcut Desktop/Start Menu bằng script; không kèm launcher EXE hay hình ảnh, QR hoặc chức năng quyên góp.

## Yêu cầu

- Windows 10/11 64-bit, PowerShell 5.1, quyền quản trị khi chuyển driver thật.
- Hai gói driver **đã giải nén đầy đủ**, không chứa trong repo này.
- INF trong mỗi thư mục phải thực sự hỗ trợ `PCI\VEN_10DE&DEV_1F0B` qua mục `.NTamd64`; việc có mã thiết bị **không tự chứng minh** rằng gói driver tương thích hoặc có chữ ký hợp lệ.

## Sử dụng

1. Giải nén bộ mã ở một thư mục cố định.
2. Chạy `Chay-CMP40HX-DriverToggle.cmd` hoặc `Chay-CMP40HX-DriverToggle.vbs`.
3. Trong **Thiết lập driver**, chọn thư mục gói driver **Làm việc** và **Chơi game**; công cụ tự tìm INF.
4. Kiểm tra hai hồ sơ và phiên bản nhận diện đúng trước khi thực hiện chuyển.
5. Đóng ứng dụng dùng GPU, đánh dấu xác nhận và mới bấm nút chuyển.
6. Nếu Windows yêu cầu, phải khởi động lại.

Ví dụ từ máy kiểm thử của người dùng (không phải tên file bắt buộc):

| Hồ sơ | INF tìm thấy trong gói |
| --- | --- |
| Làm việc / AI | `Display.Driver\nvaci.inf` (bộ 617.14 đã mod) |
| Chơi game | `Display.Driver\nvaei.inf` (bộ 460 đã mod) |

## Mô phỏng và kiểm tra trước khi dùng thật

Chạy `KiemThu-MoPhong.cmd` hoặc trực tiếp:

```powershell
powershell.exe -NoProfile -File .\CMP40HX-DriverToggle.ps1 -Simulation -SelfTest
powershell.exe -NoProfile -File .\CMP40HX-DriverToggle.ps1 -ScanFolder 'C:\duong-dan\driver-da-giai-nen'
```

Lệnh `-ScanFolder` chỉ quét INF. File trong `simulation-fixtures/` là dữ liệu thử **không phải driver thật**.

## Bảo mật, riêng tư và giới hạn

- Mã PowerShell, VBS, CMD được công bố để kiểm tra; không kèm driver NVIDIA, chương trình EXE.
- Ứng dụng có thể yêu cầu nâng quyền, chạy PowerShell ẩn qua VBS và dùng Windows SetupAPI để chuyển driver. Những hành vi này có thể bị hệ thống bảo mật cảnh báo; cảnh báo không tự chứng minh có mã độc, việc quét không đảm bảo phần mềm tuyệt đối an toàn.
- Không đưa lên GitHub các file `cmp40hx-profiles*.json`, `cmp40hx-*.log`, `*.invalid-*`, driver mod và gói cài riêng vì có thể chứa đường dẫn máy, log hoặc file không được phép phân phối.
- **Chưa kiểm thử trực tiếp bản công khai đã lược bỏ thành phần đồ họa trên Windows/CMP 40HX.** Phải thử mô phỏng và xác nhận giao diện trước khi chuyển driver thật.

## Nguồn và bản quyền

Đây là mã công cụ hỗ trợ quản trị driver, **không liên kết với NVIDIA, Riot Games hay Microsoft**. Không bao gồm gói driver bên thứ ba. Chưa ấn định giấy phép nguồn mở; cần xác minh quyền sử dụng mã gốc trước khi cấp giấy phép phân phối/sửa đổi.
