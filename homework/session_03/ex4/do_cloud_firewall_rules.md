# Cấu hình DigitalOcean Cloud Firewall cho Bài 4

Tài liệu này trình bày cấu hình Cloud Firewall cần áp dụng trên DigitalOcean (DO) Console để người dùng ngoài internet truy cập được hai cổng 8080 (Beta App) và 8090 (Internal App). Máy chủ thực hành của bài không nằm trên nền tảng DigitalOcean, vì vậy nội dung dưới đây là cấu hình cần áp dụng trên DO, được viết thành các bước và bảng rule để áp dụng trực tiếp khi triển khai trên Droplet.

## 1. Các bước thao tác trên DO Console

1. Đăng nhập DigitalOcean Control Panel.
2. Ở menu bên trái chọn Networking, sau đó chọn tab Firewalls.
3. Chọn firewall đang gắn với Droplet (ví dụ `fw-halo`). Nếu chưa có thì chọn Create Firewall và đặt tên.
4. Mở tab Rules, tìm phần Inbound Rules, chọn Edit.
5. Chọn New rule, loại Custom, giao thức TCP, Port Range `8080`, Sources để mặc định All IPv4 và All IPv6.
6. Chọn New rule lần nữa, loại Custom, giao thức TCP, Port Range `8090`, Sources All IPv4 và All IPv6 (xem khuyến nghị giới hạn nguồn ở mục 4).
7. Kiểm tra các rule SSH (cổng 2222) và HTTP (cổng 80) đã có sẵn, chọn Save.
8. Ở phần Apply to Droplets, bảo đảm Droplet `halo` nằm trong danh sách (có thể gắn theo tên Droplet hoặc theo Tag).

## 2. Bảng Inbound Rules

| Type    | Protocol | Port Range | Sources                | Ghi chú                          |
|---------|----------|------------|------------------------|----------------------------------|
| Custom  | TCP      | 2222       | All IPv4, All IPv6     | SSH (sshd đã đổi sang cổng 2222) |
| HTTP    | TCP      | 80         | All IPv4, All IPv6     | Site chính my-web                |
| Custom  | TCP      | 8080       | All IPv4, All IPv6     | Beta App (bài 4)                 |
| Custom  | TCP      | 8090       | All IPv4, All IPv6     | Internal App (bài 4)             |

## 3. Bảng Outbound Rules

| Type | Protocol | Port Range | Destinations       | Ghi chú                                         |
|------|----------|------------|--------------------|-------------------------------------------------|
| ICMP | ICMP     | -          | All IPv4, All IPv6 | Cho phép ping ra ngoài                          |
| All TCP | TCP   | All ports  | All IPv4, All IPv6 | Cho phép máy chủ truy cập apt, DNS qua TCP, v.v. |
| All UDP | UDP   | All ports  | All IPv4, All IPv6 | Cho phép DNS, NTP                               |

Đây là bộ Outbound mặc định của DigitalOcean khi tạo firewall mới, giữ nguyên để máy chủ cập nhật gói và phân giải tên miền bình thường.

## 4. Vì sao phải mở cả hai lớp tường lửa

Lưu lượng từ internet đi vào Droplet phải qua hai lớp độc lập:

```
Internet -> [DO Cloud Firewall] -> [UFW trên Droplet] -> Nginx (8080, 8090)
```

- Cloud Firewall lọc ở mức hạ tầng của nhà cung cấp, gói tin bị chặn không bao giờ tới Droplet.
- UFW lọc ở mức hệ điều hành bên trong Droplet.
- Chỉ cần một trong hai lớp chặn thì kết nối vẫn bị timeout. Vì vậy cổng 8080 và 8090 phải được mở đồng thời ở UFW (`sudo ufw allow 8080/tcp`, `sudo ufw allow 8090/tcp`) và ở Cloud Firewall.
- Dùng hai lớp theo nguyên tắc phòng thủ nhiều tầng: nếu một lớp bị cấu hình sai, lớp còn lại vẫn hạn chế được bề mặt tấn công.

## 5. Khuyến nghị bảo mật

Internal App là môi trường nội bộ nên không nên mở cho toàn bộ internet. Trong rule Custom TCP 8090, thay Sources mặc định bằng địa chỉ IP công cộng của văn phòng hoặc dải VPN của nhóm, ví dụ `203.0.113.10/32`. Khi đó chỉ mạng văn phòng truy cập được Internal App, các nguồn khác bị Cloud Firewall chặn trước khi tới Droplet. Beta App có thể giữ All IPv4 và All IPv6 nếu cần cho người dùng thử nghiệm bên ngoài.

Với bài thực hành này, để kiểm tra từ máy cá nhân (IP công cộng `113.161.72.19`), có thể tạm dùng Sources `113.161.72.19/32` cho cổng 8090 thay vì All IPv4.
