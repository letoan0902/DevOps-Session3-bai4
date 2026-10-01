# DevOps - Session 03 - Bài 4: Chạy song song nhiều cổng dịch vụ (Nginx Virtual Hosts)

Bài thực hành cấu hình Nginx chạy song song hai trang web tĩnh độc lập (Beta App và Internal App) trên cùng một IP thông qua phân chia cổng 8080 và 8090, đồng thời thiết lập UFW và trình bày cấu hình DigitalOcean Cloud Firewall để người dùng ngoài internet truy cập được.

## Mục lục

- Báo cáo chi tiết: [homework/session_03/ex4/README.md](homework/session_03/ex4/README.md)
- Nhật ký Terminal: [homework/session_03/ex4/terminal_log.txt](homework/session_03/ex4/terminal_log.txt)
- Cấu hình Nginx: [homework/session_03/ex4/multi-port.conf](homework/session_03/ex4/multi-port.conf)
- Cloud Firewall: [homework/session_03/ex4/do_cloud_firewall_rules.md](homework/session_03/ex4/do_cloud_firewall_rules.md)

## Danh sách file

```
DevOps-Session3-bai4/
|-- README.md
`-- homework/
    `-- session_03/
        `-- ex4/
            |-- README.md                    (báo cáo)
            |-- multi-port.conf              (hai server block: 8080 và 8090)
            |-- beta-app/
            |   `-- index.html               (trang Beta App)
            |-- internal-app/
            |   `-- index.html               (trang Internal App)
            |-- terminal_log.txt             (nhật ký Terminal)
            |-- deploy_multi_port.sh         (script triển khai idempotent)
            `-- do_cloud_firewall_rules.md   (bảng rule DO Cloud Firewall)
```
