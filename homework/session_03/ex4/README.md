# Bài 4 - Chạy song song nhiều cổng dịch vụ (Nginx Virtual Hosts)

Môn: DevOps - Session 03
Thực hiện: Thứ Sáu, 2026-10-02, khoảng 14:00 đến 14:45 (múi giờ +0700)

## 1. Mục tiêu và yêu cầu

Cần triển khai hai môi trường thử nghiệm độc lập là Beta App và Internal App chạy song song trên cùng một máy chủ, cùng một địa chỉ IP, phân biệt với nhau bằng số cổng.

| Thành phần   | Cổng | Thư mục mã nguồn                 | Nội dung trang           |
|--------------|------|----------------------------------|--------------------------|
| Beta App     | 8080 | `/var/www/beta-app/html/`        | Tiêu đề "Beta App"       |
| Internal App | 8090 | `/var/www/internal-app/html/`    | Tiêu đề "Internal App"   |
| my-web (cũ)  | 80   | giữ nguyên, không thay đổi       | Site chính của máy chủ   |

Yêu cầu đi kèm:

- Mỗi thư mục có một `index.html` với tiêu đề tương ứng.
- Hai server block trong cùng một file `/etc/nginx/sites-available/multi-port.conf`.
- Mở cổng 8080 và 8090 trên UFW và trên DigitalOcean Cloud Firewall.
- Kiểm tra bằng `curl http://<IP>:8080` và `curl http://<IP>:8090`.

## 2. Kiến thức nền: virtual host theo cổng và theo tên

Virtual host là cơ chế để một tiến trình Nginx phục vụ nhiều website khác nhau. Nginx quyết định server block nào xử lý một yêu cầu bằng hai bước:

1. Chọn các server block có `listen` khớp với địa chỉ IP và cổng mà gói tin đến.
2. Nếu có nhiều block cùng lắng nghe một cổng, so khớp tiếp giá trị `Host` trong yêu cầu với `server_name`. Không khớp block nào thì dùng block mặc định của cổng đó (block đầu tiên, hoặc block có `default_server`).

Từ đó có hai kiểu phân chia:

| Tiêu chí              | Virtual host theo cổng (port-based)           | Virtual host theo tên (name-based)               |
|-----------------------|-----------------------------------------------|--------------------------------------------------|
| Khóa phân biệt        | Số cổng trong `listen`                        | Tên miền trong `server_name` (header `Host`)     |
| Địa chỉ truy cập      | `http://IP:8080`, `http://IP:8090`            | `http://beta.example.com`, `http://app.example.com` |
| Cần tên miền / DNS    | Không                                         | Có, mỗi site một bản ghi DNS trỏ về cùng IP      |
| Cần mở thêm cổng      | Có, mỗi site một cổng (UFW, Cloud Firewall)   | Không, dùng chung cổng 80 hoặc 443               |
| Phù hợp               | Môi trường thử nghiệm, nội bộ, không có DNS   | Website công khai, chạy thật                     |
| Nhược điểm            | Người dùng phải nhớ cổng, một số mạng chặn cổng lạ | Phải quản lý DNS, cần chứng chỉ cho từng tên |

Bài này dùng kiểu theo cổng vì hai môi trường thử nghiệm chưa có tên miền riêng. Do khóa phân biệt là cổng nên `server_name` chỉ cần đặt giá trị `_` (tên không khớp tên miền thật, dùng làm "bắt mọi tên").

Sơ đồ luồng yêu cầu:

```
                                +-------------------------------------------+
                                |  Máy chủ halo - 103.116.104.228           |
                                |                                           |
                                |  Nginx 1.24.0 (một tiến trình master)     |
 Client                         |                                           |
   |                            |   server block "beta"                     |
   |-- http://IP:8080 --------> |     listen 8080                           |
   |                            |     root /var/www/beta-app/html           |
   |                            |         -> index.html  ("Beta App")       |
   |                            |                                           |
   |-- http://IP:8090 --------> |   server block "internal"                 |
   |                            |     listen 8090                           |
   |                            |     root /var/www/internal-app/html       |
   |                            |         -> index.html  ("Internal App")   |
   |                            |                                           |
   |-- http://IP:80 ----------> |   site my-web (giữ nguyên)                |
                                |     listen 80                             |
                                +-------------------------------------------+
```

Lưu lượng từ internet đi qua hai lớp tường lửa trước khi tới Nginx:

```
Internet -> [DO Cloud Firewall] -> [UFW trên máy chủ] -> Nginx (80, 8080, 8090)
```

## 3. Môi trường thực hiện

| Mục                 | Giá trị                                                                 |
|---------------------|-------------------------------------------------------------------------|
| Hệ điều hành        | Ubuntu 24.04.3 LTS                                                      |
| Hostname / IP       | `halo` / `103.116.104.228`                                              |
| Tài khoản           | `devops` (uid 1001, thuộc nhóm sudo, sudo có hỏi mật khẩu)              |
| SSH                 | Cổng 2222, khóa `~/.ssh/id_ed25519_ptit_s02`                            |
| Nginx               | `nginx/1.24.0 (Ubuntu)`, site `my-web` đang chạy cổng 80                |
| Máy cá nhân         | Windows, Git Bash, curl 8.15.0, IP công cộng `113.161.72.19`            |
| Dịch vụ liên quan   | sshd, nginx, ufw                                                        |

Trạng thái UFW trước khi làm bài: active, mặc định `deny (incoming)`, `allow (outgoing)`, đã cho phép `2222/tcp` và `80/tcp` (cả IPv4 và IPv6).

Kết nối vào máy chủ:

```
$ ssh -p 2222 -i ~/.ssh/id_ed25519_ptit_s02 devops@103.116.104.228
```

Lệnh `sudo ufw status verbose` xác nhận bốn rule ban đầu: `2222/tcp` và `80/tcp`, mỗi rule có bản IPv4 và IPv6 (chi tiết trong `terminal_log.txt`).

## 4. Bước 1 - Kiểm tra cổng 8080 và 8090 còn trống

Nếu một tiến trình khác đã giữ cổng thì Nginx sẽ không bind được và lệnh `nginx -t` hoặc `reload` báo lỗi. Vì vậy kiểm tra trước:

```
devops@halo:~$ sudo ss -tlnp | grep -E ":(8080|8090)"
devops@halo:~$ echo $?
1
```

Không có dòng nào được in ra (grep trả mã thoát 1), tức là cả hai cổng còn trống. Hiện Nginx chỉ lắng nghe cổng 80:

```
devops@halo:~$ sudo ss -tlnp | grep nginx
LISTEN 0      511            0.0.0.0:80      0.0.0.0:*    users:(("nginx",pid=9766,fd=5),("nginx",pid=9765,fd=5),("nginx",pid=9764,fd=5))
LISTEN 0      511               [::]:80         [::]:*    users:(("nginx",pid=9766,fd=6),("nginx",pid=9765,fd=6),("nginx",pid=9764,fd=6))
```

Giải thích các tùy chọn của `ss`: `-t` chỉ lấy TCP, `-l` chỉ lấy socket đang lắng nghe, `-n` hiển thị số cổng thay vì tên dịch vụ, `-p` hiển thị tiến trình sở hữu (cần `sudo`).

## 5. Bước 2 - Tạo thư mục mã nguồn và index.html

### 5.1 Tạo thư mục và phân quyền

```
devops@halo:~$ sudo mkdir -p /var/www/beta-app/html /var/www/internal-app/html
devops@halo:~$ sudo chown -R devops:www-data /var/www/beta-app /var/www/internal-app
devops@halo:~$ sudo find /var/www/beta-app /var/www/internal-app -type d -exec chmod 750 {} +
```

Lý do chọn quyền:

- Chủ sở hữu là `devops` để tài khoản triển khai chỉnh sửa nội dung mà không cần `sudo`.
- Nhóm sở hữu là `www-data` (tài khoản chạy worker của Nginx) để Nginx đọc được file.
- Thư mục `750` (`rwxr-x---`): chủ ghi được, nhóm `www-data` đọc và duyệt được, người khác không có quyền gì.
- File `640` (`rw-r-----`): chủ đọc và ghi, nhóm `www-data` chỉ đọc, người khác không có quyền.
- Nguyên tắc đặc quyền tối thiểu: Nginx chỉ cần đọc, không cần ghi vào mã nguồn.

### 5.2 Tạo hai file index.html

Hai trang dùng HTML5 hợp lệ (`<!DOCTYPE html>`, `lang="vi"`, `charset="UTF-8"`), CSS nội tuyến, mỗi trang một màu chủ đạo (Beta App màu xanh dương, Internal App màu cam) để phân biệt bằng mắt, và hiển thị rõ cổng đang phục vụ.

```
devops@halo:~$ nano /var/www/beta-app/html/index.html
devops@halo:~$ nano /var/www/internal-app/html/index.html
devops@halo:~$ sudo find /var/www/beta-app /var/www/internal-app -type f -exec chmod 640 {} +
```

Các phần chính của `/var/www/beta-app/html/index.html` (995 byte, toàn văn trong thư mục nộp):

```html
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>Beta App</title>
  <style> ... CSS nội tuyến, màu chủ đạo #1f6feb ... </style>
</head>
<body>
  <div class="box">
    <h1>Beta App</h1>
    <p>Đây là môi trường thử nghiệm Beta, được phục vụ bởi Nginx trên cổng <span class="port">8080</span>.</p>
    ...
  </div>
</body>
</html>
```

File `/var/www/internal-app/html/index.html` (994 byte) có cấu trúc giống hệt, khác ở `<title>` và `<h1>` là "Internal App", màu chủ đạo `#d9480f`, cổng hiển thị 8090 (xem file `internal-app/index.html` trong thư mục nộp).

### 5.3 Kiểm tra quyền và kích thước

```
devops@halo:~$ ls -la /var/www/beta-app/html /var/www/internal-app/html
/var/www/beta-app/html:
total 12
drwxr-x--- 2 devops www-data 4096 Oct  2 14:12 .
drwxr-x--- 3 devops www-data 4096 Oct  2 14:08 ..
-rw-r----- 1 devops www-data  995 Oct  2 14:12 index.html

/var/www/internal-app/html:
total 12
drwxr-x--- 2 devops www-data 4096 Oct  2 14:13 .
drwxr-x--- 3 devops www-data 4096 Oct  2 14:08 ..
-rw-r----- 1 devops www-data  994 Oct  2 14:13 index.html
devops@halo:~$ wc -c /var/www/beta-app/html/index.html /var/www/internal-app/html/index.html
 995 /var/www/beta-app/html/index.html
 994 /var/www/internal-app/html/index.html
1989 total
```

Xác nhận chuỗi quyền truy cập từ thư mục gốc đến file, và xác nhận tài khoản `www-data` đọc được:

```
devops@halo:~$ namei -m /var/www/beta-app/html/index.html
f: /var/www/beta-app/html/index.html
 drwxr-xr-x /
 drwxr-xr-x var
 drwxr-xr-x www
 drwxr-x--- beta-app
 drwxr-x--- html
 -rw-r----- index.html
devops@halo:~$ sudo -u www-data head -n 1 /var/www/beta-app/html/index.html
<!DOCTYPE html>
```

Kích thước 995 và 994 byte sẽ được đối chiếu lại với header `Content-Length` ở Bước 8.

## 6. Bước 3 - Viết file cấu hình multi-port.conf

Theo gợi ý của đề, đặt cả hai server block trong một file duy nhất:

```
devops@halo:~$ sudo nano /etc/nginx/sites-available/multi-port.conf
```

Nội dung server block đầu tiên (file nộp `multi-port.conf` còn có block thứ hai cho cổng 8090 với cấu trúc y hệt, chỉ khác cổng, `root` và tên file log):

```nginx
server {
    # Lắng nghe IPv4 và IPv6 trên cổng 8080
    listen 8080;
    listen [::]:8080;

    # Virtual host theo cổng: không phân biệt tên miền nên dùng server_name "_"
    server_name _;

    # Thư mục mã nguồn của Beta App
    root /var/www/beta-app/html;
    index index.html;

    # Log riêng cho từng site để dễ truy vết
    access_log /var/log/nginx/beta-app.access.log;
    error_log  /var/log/nginx/beta-app.error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Block thứ hai: `listen 8090; listen [::]:8090; root /var/www/internal-app/html;` và log `internal-app.access.log`, `internal-app.error.log`.

Giải thích từng chỉ thị:

| Chỉ thị                          | Ý nghĩa                                                                                  |
|----------------------------------|------------------------------------------------------------------------------------------|
| `listen 8080;`                   | Lắng nghe IPv4 (mọi địa chỉ, `0.0.0.0`) trên cổng 8080                                   |
| `listen [::]:8080;`              | Lắng nghe IPv6 trên cổng 8080 (UFW đã mở cả rule v6 nên cần lắng nghe cả hai họ địa chỉ) |
| `server_name _;`                 | Tên giữ chỗ, không trùng tên miền thật; block nhận mọi yêu cầu tới cổng này              |
| `root ...;`                      | Thư mục gốc để ánh xạ URL thành đường dẫn file                                           |
| `index index.html;`              | File trả về khi URL kết thúc bằng `/`                                                    |
| `access_log`, `error_log`        | Tách log theo từng site, thuận tiện đối chiếu và gỡ lỗi                                  |
| `try_files $uri $uri/ =404;`     | Thử file đúng tên, rồi thư mục, cuối cùng trả 404 thay vì rơi vào xử lý khác             |

Hai server block không xung đột `server_name` vì nằm ở hai cổng khác nhau. Block ở cổng 80 của `my-web` nằm trong file riêng nên không bị ảnh hưởng.

## 7. Bước 4 - Bật site, kiểm tra cú pháp và reload Nginx

Nginx chỉ nạp các file nằm trong `sites-enabled`. Cách chuẩn là tạo symlink từ `sites-available`:

```
devops@halo:~$ sudo ln -s /etc/nginx/sites-available/multi-port.conf /etc/nginx/sites-enabled/multi-port.conf
devops@halo:~$ ls -l /etc/nginx/sites-enabled/
total 0
lrwxrwxrwx 1 root root 42 Oct  2 14:16 multi-port.conf -> /etc/nginx/sites-available/multi-port.conf
lrwxrwxrwx 1 root root 33 Sep 29 20:41 my-web -> /etc/nginx/sites-available/my-web
```

Luôn kiểm tra cú pháp trước khi nạp lại cấu hình:

```
devops@halo:~$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
devops@halo:~$ sudo systemctl reload nginx
```

`reload` gửi tín hiệu để master nạp cấu hình mới và thay worker mới một cách mềm mại, các kết nối đang xử lý không bị ngắt. Nếu `nginx -t` lỗi thì không reload, Nginx tiếp tục chạy bằng cấu hình cũ.

```
devops@halo:~$ sudo systemctl status nginx --no-pager
* nginx.service - A high performance web server and a reverse proxy server
     Active: active (running) since Thu 2026-10-01 19:22:48 +07; 18h ago
    Process: 18522 ExecReload=/usr/sbin/nginx -g daemon on; master_process on; -s reload (code=exited, status=0/SUCCESS)
   Main PID: 9764 (nginx)
     CGroup: /system.slice/nginx.service
             |-9764 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"
             |-18523 "nginx: worker process"
             `-18524 "nginx: worker process"
```

Master giữ nguyên PID 9764 (không bị khởi động lại), chỉ có worker mới 18523 và 18524. Kiểm tra các cổng đang lắng nghe:

```
devops@halo:~$ sudo ss -tlnp | grep nginx
LISTEN 0      511          0.0.0.0:8080      0.0.0.0:*    users:(("nginx",pid=18524,fd=7),("nginx",pid=18523,fd=7),("nginx",pid=9764,fd=7))
LISTEN 0      511            0.0.0.0:80      0.0.0.0:*    users:(("nginx",pid=18524,fd=5),("nginx",pid=18523,fd=5),("nginx",pid=9764,fd=5))
LISTEN 0      511          0.0.0.0:8090      0.0.0.0:*    users:(("nginx",pid=18524,fd=9),("nginx",pid=18523,fd=9),("nginx",pid=9764,fd=9))
LISTEN 0      511             [::]:8080         [::]:*    users:(("nginx",pid=18524,fd=8),("nginx",pid=18523,fd=8),("nginx",pid=9764,fd=8))
LISTEN 0      511               [::]:80         [::]:*    users:(("nginx",pid=18524,fd=6),("nginx",pid=18523,fd=6),("nginx",pid=9764,fd=6))
LISTEN 0      511             [::]:8090         [::]:*    users:(("nginx",pid=18524,fd=10),("nginx",pid=18523,fd=10),("nginx",pid=9764,fd=10))
```

Nginx hiện lắng nghe đủ ba cổng 80, 8080, 8090 trên cả IPv4 (`0.0.0.0`) và IPv6 (`[::]`). Cổng 80 vẫn do `my-web` phục vụ.

## 8. Bước 5 - Chứng minh vai trò của tường lửa

Mục đích: chứng minh rằng Nginx chạy đúng nhưng người dùng ngoài internet vẫn chưa truy cập được khi chưa mở cổng ở UFW. Đây là lý do cần Bước 6 và Bước 7.

### 8.1 Trên máy chủ, gọi qua loopback

Kết nối tới `127.0.0.1` đi qua giao diện loopback nên không bị UFW chặn (UFW mặc định cho phép lưu lượng loopback):

```
devops@halo:~$ curl -s http://127.0.0.1:8080 | grep "<title>"
  <title>Beta App</title>
devops@halo:~$ curl -s http://127.0.0.1:8090 | grep "<title>"
  <title>Internal App</title>
```

### 8.2 Trên máy cá nhân, gọi qua IP công cộng

```
$ curl -m 5 http://103.116.104.228:8080
curl: (28) Connection timed out after 5002 milliseconds
$ echo $?
28
$ curl -m 5 http://103.116.104.228:8090
curl: (28) Connection timed out after 5004 milliseconds
$ echo $?
28
```

Mã thoát 28 là hết thời gian chờ (`-m 5` giới hạn 5 giây). Gói SYN đến cổng 8080 và 8090 bị UFW âm thầm bỏ (policy `deny`, không trả RST) nên client chỉ chờ tới khi quá hạn.

### 8.3 Đối chiếu nhật ký UFW trên máy chủ

```
devops@halo:~$ sudo grep -E "UFW BLOCK.*DPT=(8080|8090)" /var/log/ufw.log | tail -n 4
2026-10-02T14:21:34.208415+07:00 halo kernel: [412894.331905] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:7c:21:fa:16:3e:0a:44:90:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=108 ID=21744 DF PROTO=TCP SPT=51872 DPT=8080 WINDOW=64240 RES=0x00 SYN URGP=0
2026-10-02T14:21:37.214809+07:00 halo kernel: [412897.337118] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:7c:21:fa:16:3e:0a:44:90:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=108 ID=21751 DF PROTO=TCP SPT=51872 DPT=8080 WINDOW=64240 RES=0x00 SYN URGP=0
2026-10-02T14:21:49.640226+07:00 halo kernel: [412909.763377] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:7c:21:fa:16:3e:0a:44:90:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=108 ID=21789 DF PROTO=TCP SPT=51879 DPT=8090 WINDOW=64240 RES=0x00 SYN URGP=0
2026-10-02T14:21:52.646511+07:00 halo kernel: [412912.769654] [UFW BLOCK] IN=eth0 OUT= MAC=fa:16:3e:5b:7c:21:fa:16:3e:0a:44:90:08:00 SRC=113.161.72.19 DST=103.116.104.228 LEN=52 TOS=0x00 PREC=0x00 TTL=108 ID=21796 DF PROTO=TCP SPT=51879 DPT=8090 WINDOW=64240 RES=0x00 SYN URGP=0
```

Các dòng `[UFW BLOCK]` với `SRC=113.161.72.19` (máy cá nhân), `DPT=8080` và `DPT=8090` cho thấy gói SYN (kèm lần gửi lại sau 3 giây) đã tới máy chủ nhưng bị UFW chặn.

Kết luận của bước: Nginx hoạt động đúng, nguyên nhân không truy cập được từ ngoài chính là tường lửa.

## 9. Bước 6 - Mở cổng trên UFW

```
devops@halo:~$ sudo ufw allow 8080/tcp
Rule added
Rule added (v6)
devops@halo:~$ sudo ufw allow 8090/tcp
Rule added
Rule added (v6)
devops@halo:~$ sudo ufw status numbered
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 2222/tcp                   ALLOW IN    Anywhere                  
[ 2] 80/tcp                     ALLOW IN    Anywhere                  
[ 3] 8080/tcp                   ALLOW IN    Anywhere                  
[ 4] 8090/tcp                   ALLOW IN    Anywhere                  
[ 5] 2222/tcp (v6)              ALLOW IN    Anywhere (v6)             
[ 6] 80/tcp (v6)                ALLOW IN    Anywhere (v6)             
[ 7] 8080/tcp (v6)              ALLOW IN    Anywhere (v6)             
[ 8] 8090/tcp (v6)              ALLOW IN    Anywhere (v6)             
```

Mỗi lệnh `ufw allow` tạo hai rule, một cho IPv4 (`Rule added`) và một cho IPv6 (`Rule added (v6)`). UFW áp dụng ngay, không cần `ufw reload` hay khởi động lại. Quy tắc SSH cổng 2222 giữ nguyên nên phiên làm việc không bị ảnh hưởng.

## 10. Bước 7 - Mở cổng trên DigitalOcean Cloud Firewall

Lưu ý về phạm vi: máy chủ dùng để thực hành trong bài này không nằm trên nền tảng DigitalOcean, nên phần này trình bày cấu hình cần áp dụng trên DigitalOcean (DO) Console cho một Droplet thật, không phải thao tác đã chạy trên máy chủ thực hành. Bảng rule đầy đủ nằm trong file `do_cloud_firewall_rules.md`.

### 10.1 Các bước trên DO Console

1. Đăng nhập DigitalOcean Control Panel.
2. Menu bên trái chọn Networking, rồi chọn tab Firewalls.
3. Chọn firewall đang gắn với Droplet (hoặc Create Firewall nếu chưa có).
4. Ở phần Inbound Rules chọn Edit.
5. Chọn New rule, loại Custom, giao thức TCP, Port Range `8080`, Sources All IPv4 và All IPv6.
6. Chọn New rule lần nữa, loại Custom, giao thức TCP, Port Range `8090`, Sources All IPv4 và All IPv6.
7. Chọn Save, kiểm tra Droplet đã nằm trong mục Apply to Droplets.

### 10.2 Bảng Inbound Rules

| Type    | Protocol | Port Range | Sources            | Ghi chú                |
|---------|----------|------------|--------------------|------------------------|
| Custom  | TCP      | 2222       | All IPv4, All IPv6 | SSH                    |
| HTTP    | TCP      | 80         | All IPv4, All IPv6 | Site chính my-web      |
| Custom  | TCP      | 8080       | All IPv4, All IPv6 | Beta App               |
| Custom  | TCP      | 8090       | All IPv4, All IPv6 | Internal App           |

### 10.3 Bảng Outbound Rules

Giữ bộ rule Outbound mặc định của DO (ICMP, All TCP, All UDP tới All IPv4 và All IPv6) để máy chủ cập nhật gói và phân giải tên miền; bảng đầy đủ trong `do_cloud_firewall_rules.md`.

### 10.4 Vì sao phải mở cả hai lớp

- Cloud Firewall hoạt động ở tầng hạ tầng của nhà cung cấp, gói tin bị chặn không bao giờ tới Droplet.
- UFW hoạt động bên trong hệ điều hành của Droplet.
- Gói tin phải được cho phép ở cả hai lớp mới tới Nginx. Chỉ cần một lớp chặn là client vẫn bị timeout, và triệu chứng giống hệt nhau, nên khi gỡ lỗi phải kiểm tra từng lớp.
- Hai lớp độc lập còn giúp phòng thủ nhiều tầng: lỡ cấu hình sai một lớp thì lớp còn lại vẫn giới hạn được bề mặt tấn công.

### 10.5 Khuyến nghị bảo mật

Internal App là môi trường nội bộ nên không nên mở cho mọi nguồn. Ở rule TCP 8090, thay Sources mặc định bằng IP công cộng của văn phòng hoặc dải VPN của nhóm (ví dụ `203.0.113.10/32`). Khi đó chỉ mạng văn phòng truy cập được Internal App, các nguồn khác bị chặn ngay ở Cloud Firewall. Beta App có thể giữ All IPv4 và All IPv6 nếu cần cho người dùng thử nghiệm bên ngoài. Có thể giới hạn tương tự ở UFW bằng `sudo ufw allow from 203.0.113.10 to any port 8090 proto tcp` thay cho `sudo ufw allow 8090/tcp`.

## 11. Bước 8 - Kiểm tra kết quả từ máy cá nhân

### 11.1 Lệnh theo đề bài

```
$ curl http://103.116.104.228:8080
<!DOCTYPE html>
<html lang="vi">
<head>
  <title>Beta App</title>
    <h1>Beta App</h1>
    <p>Đây là môi trường thử nghiệm Beta, được phục vụ bởi Nginx trên cổng <span class="port">8080</span>.</p>
</html>
```

```
$ curl http://103.116.104.228:8090
<!DOCTYPE html>
<html lang="vi">
<head>
  <title>Internal App</title>
    <h1>Internal App</h1>
    <p>Đây là môi trường nội bộ, được phục vụ bởi Nginx trên cổng <span class="port">8090</span>.</p>
</html>
```

Mỗi lệnh in ra toàn bộ trang HTML (bản trình bày này lược các dòng CSS và dòng mô tả thứ hai; toàn văn nằm trong `terminal_log.txt`).

### 11.2 Kiểm tra header

```
$ curl -I http://103.116.104.228:8080
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Fri, 02 Oct 2026 07:39:02 GMT
Content-Type: text/html
Content-Length: 995
Last-Modified: Fri, 02 Oct 2026 07:12:41 GMT
Connection: keep-alive
ETag: "6abf5969-3e3"
Accept-Ranges: bytes

$ curl -I http://103.116.104.228:8090
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Fri, 02 Oct 2026 07:39:10 GMT
Content-Type: text/html
Content-Length: 994
Last-Modified: Fri, 02 Oct 2026 07:13:20 GMT
Connection: keep-alive
ETag: "6abf5990-3e2"
Accept-Ranges: bytes
```

Đối chiếu: `Content-Length` 995 và 994 khớp đúng kết quả `wc -c` ở Bước 2. Phần sau dấu gạch ngang của `ETag` (`3e3` và `3e2` ở dạng thập lục phân) chính là kích thước file 995 và 994 byte. `Last-Modified` (07:12:41 GMT và 07:13:20 GMT) tương ứng 14:12:41 và 14:13:20 giờ địa phương (+0700), trùng thời điểm tạo file. Header `Date` ở múi giờ GMT là 07:39, tức 14:39 giờ Việt Nam.

### 11.3 Trích tiêu đề và kiểm tra các trường hợp khác

```
$ curl -s http://103.116.104.228:8080 | grep -o "<title>.*</title>"
<title>Beta App</title>
$ curl -s http://103.116.104.228:8090 | grep -o "<title>.*</title>"
<title>Internal App</title>
$ curl -sI http://103.116.104.228 | head -n 1
HTTP/1.1 200 OK
$ curl -s -o /dev/null -w "%{http_code}\n" http://103.116.104.228:8080/khong-co.html
404
```

Cổng 80 vẫn phản hồi `200 OK` (site `my-web` không bị ảnh hưởng). Đường dẫn không tồn tại trả `404` đúng như chỉ thị `try_files ... =404`.

### 11.4 Nhật ký truy cập riêng của từng site

```
devops@halo:~$ sudo tail -n 6 /var/log/nginx/beta-app.access.log
127.0.0.1 - - [02/Oct/2026:14:19:07 +0700] "GET / HTTP/1.1" 200 995 "-" "curl/8.5.0"
113.161.72.19 - - [02/Oct/2026:14:38:41 +0700] "GET / HTTP/1.1" 200 995 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:14:39:02 +0700] "HEAD / HTTP/1.1" 200 0 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:14:39:31 +0700] "GET / HTTP/1.1" 200 995 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:14:40:20 +0700] "GET /khong-co.html HTTP/1.1" 404 162 "-" "curl/8.15.0"
devops@halo:~$ sudo tail -n 6 /var/log/nginx/internal-app.access.log
127.0.0.1 - - [02/Oct/2026:14:19:15 +0700] "GET / HTTP/1.1" 200 994 "-" "curl/8.5.0"
113.161.72.19 - - [02/Oct/2026:14:38:49 +0700] "GET / HTTP/1.1" 200 994 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:14:39:10 +0700] "HEAD / HTTP/1.1" 200 0 "-" "curl/8.15.0"
113.161.72.19 - - [02/Oct/2026:14:39:38 +0700] "GET / HTTP/1.1" 200 994 "-" "curl/8.15.0"
```

Nhận xét:

- Mỗi site ghi vào file log riêng, yêu cầu tới cổng 8080 chỉ nằm trong `beta-app.access.log` và yêu cầu tới cổng 8090 chỉ nằm trong `internal-app.access.log`, chứng tỏ hai server block hoạt động độc lập.
- Cột kích thước phản hồi là 995 (Beta App) và 994 (Internal App), trùng kích thước file; yêu cầu `HEAD` ghi 0 vì không có thân phản hồi.
- Các lần timeout ở Bước 5 không xuất hiện trong log của Nginx vì gói tin bị UFW chặn trước khi tới Nginx.
- Hai file `*.error.log` đều trống (0 byte), không có lỗi trong quá trình phục vụ.

## 12. Xử lý sự cố thường gặp

| Triệu chứng | Nguyên nhân | Cách chẩn đoán | Cách khắc phục |
|-------------|-------------|----------------|----------------|
| `nginx -t` hoặc reload báo `bind() to 0.0.0.0:8080 failed (98: Address already in use)` | Cổng đã bị tiến trình khác chiếm | `sudo ss -tlnp \| grep :8080` xem PID và tên tiến trình | Dừng tiến trình đó, hoặc đổi sang cổng khác trong `listen` và trong rule tường lửa |
| `nginx -t` báo `conflicting server name "_" on 0.0.0.0:8080, ignored` | Hai server block cùng cổng, cùng `server_name` | Tìm `listen 8080` trong `/etc/nginx/sites-enabled/` | Mỗi cổng chỉ để một block, hoặc đặt `server_name` khác nhau |
| `nginx -t` thành công nhưng cổng 8080 không xuất hiện trong `ss`; `curl http://127.0.0.1:8080` báo `Connection refused` (mã 7) | Quên tạo symlink trong `sites-enabled`, hoặc quên `reload` | `ls -l /etc/nginx/sites-enabled/` không thấy `multi-port.conf` | `sudo ln -s /etc/nginx/sites-available/multi-port.conf /etc/nginx/sites-enabled/` rồi `sudo nginx -t && sudo systemctl reload nginx` |
| `curl` từ ngoài bị treo rồi `curl: (28) Connection timed out`, nhưng trên máy chủ `curl 127.0.0.1` vẫn đúng | UFW hoặc Cloud Firewall chưa mở cổng | `sudo ufw status numbered`; xem `[UFW BLOCK]` trong `/var/log/ufw.log`; kiểm tra Inbound Rules trên DO | `sudo ufw allow 8080/tcp`, `sudo ufw allow 8090/tcp` và thêm rule Custom TCP trên Cloud Firewall |
| `403 Forbidden` | Worker `www-data` không đọc được file hoặc thiếu quyền duyệt thư mục; log báo `open() ... failed (13: Permission denied)` | `namei -m /var/www/beta-app/html/index.html`; `sudo -u www-data head -n 1 <file>`; `sudo tail /var/log/nginx/beta-app.error.log` | `sudo chown -R devops:www-data /var/www/beta-app /var/www/internal-app`, thư mục `750`, file `640` |
| `404 Not Found` cho đường dẫn `/` | `root` trỏ sai thư mục hoặc thiếu `index.html` | `ls -l` thư mục gốc; đối chiếu `root` trong `multi-port.conf` | Sửa `root` cho đúng, tạo `index.html`, reload |
| Truy cập `http://IP:8080` bị trình duyệt từ chối nhưng `curl` chạy được | Trình duyệt tự đổi sang HTTPS hoặc mạng nội bộ chặn cổng lạ | Gõ rõ `http://` và cổng; thử mạng khác | Dùng đúng giao thức HTTP, hoặc đổi sang mạng cho phép cổng 8080 và 8090 |

## 13. Đối chiếu yêu cầu đề bài

| Yêu cầu của đề | Thực hiện | Bằng chứng |
|----------------|-----------|------------|
| Tạo `/var/www/beta-app/html/` và `/var/www/internal-app/html/`, mỗi nơi có một `index.html` có tiêu đề tương ứng | Tạo bằng `mkdir -p`, hai file có `<title>` và `<h1>` là "Beta App" và "Internal App" | Mục 5, `beta-app/index.html`, `internal-app/index.html` |
| Server block cổng 8080 trỏ root về beta-app | `listen 8080; root /var/www/beta-app/html;` | Mục 6, `multi-port.conf` |
| Server block cổng 8090 trỏ root về internal-app | `listen 8090; root /var/www/internal-app/html;` | Mục 6, `multi-port.conf` |
| Gợi ý một file duy nhất `multi-port.conf` chứa cả hai block | Cả hai block trong `/etc/nginx/sites-available/multi-port.conf`, bật bằng symlink | Mục 6 và 7 |
| Mở cổng 8080 và 8090 trên UFW | `sudo ufw allow 8080/tcp`, `sudo ufw allow 8090/tcp` | Mục 9 (`ufw status numbered`) |
| Mở cổng 8080 và 8090 trên DigitalOcean Cloud Firewall | Trình bày các bước và bảng rule Inbound/Outbound cần áp dụng trên DO (máy chủ thực hành không nằm trên DO) | Mục 10, `do_cloud_firewall_rules.md` |
| `curl http://<IP>:8080` trả giao diện Beta App | Trả HTML có tiêu đề "Beta App" | Mục 11.1 |
| `curl http://<IP>:8090` trả giao diện Internal App | Trả HTML có tiêu đề "Internal App" | Mục 11.1 |
| Nộp tệp cấu hình Nginx và các file index.html | Có trong `homework/session_03/ex4/` | Mục 15 |

## 14. Kết luận

- Một tiến trình Nginx phục vụ đồng thời ba site trên một IP: my-web (cổng 80), Beta App (cổng 8080), Internal App (cổng 8090). Mỗi site có thư mục mã nguồn, access log và error log riêng.
- Kiểu virtual host theo cổng đơn giản, không cần DNS, phù hợp môi trường thử nghiệm và nội bộ. Khi chuyển sang chạy thật nên dùng virtual host theo tên miền trên cổng 80 và 443.
- Quy trình an toàn khi sửa cấu hình: kiểm tra cổng trống, viết cấu hình, bật bằng symlink, `nginx -t` rồi mới `reload`, tránh làm gián đoạn site đang chạy.
- Việc mở cổng phải thực hiện ở mọi lớp tường lửa trên đường đi. Thí nghiệm ở Bước 5 cho thấy khi UFW chưa mở thì Nginx đã chạy đúng nhưng client bên ngoài vẫn bị timeout, và nhật ký `[UFW BLOCK]` xác nhận nguyên nhân.
- Phân quyền `750`/`640` với nhóm `www-data` đủ để Nginx đọc nội dung mà không mở quyền cho tài khoản khác.
- Với Internal App, nên giới hạn nguồn truy cập theo IP văn phòng thay vì mở cho mọi địa chỉ.
- Toàn bộ các bước đã được gói thành script idempotent `deploy_multi_port.sh` (đã kiểm tra cú pháp bằng `bash -n`), chạy lại nhiều lần cho cùng một kết quả.

## 15. Danh sách file nộp

Thư mục `homework/session_03/ex4/` gồm: `README.md` (báo cáo này), `multi-port.conf` (cấu hình Nginx hai server block), `beta-app/index.html` (995 byte), `internal-app/index.html` (994 byte), `terminal_log.txt` (nhật ký Terminal), `deploy_multi_port.sh` (script idempotent) và `do_cloud_firewall_rules.md` (bảng rule DO Cloud Firewall).

Chạy script trên máy chủ (đặt cả thư mục `ex4` lên máy chủ, ví dụ bằng `scp`):

```
devops@halo:~$ cd ~/ex4
devops@halo:~/ex4$ bash deploy_multi_port.sh
```
