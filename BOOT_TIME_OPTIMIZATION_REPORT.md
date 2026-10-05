# Báo cáo thay đổi thời gian boot trước và sau tối ưu rootfs

## 1. Phạm vi

Báo cáo so sánh hai boot log:

- Trước tối ưu: `log_1609_timesptamp`
- Sau tối ưu: `log_fullflow_optimized`

Mục tiêu là xác định thời gian giảm ở từng giai đoạn và phân biệt rõ:

- thay đổi do cấu hình U-Boot;
- thay đổi do ramdisk/rootfs nhỏ hơn;
- thay đổi do bỏ dịch vụ userspace;
- các thay đổi không tạo ra cải thiện hoặc gây regression.

Các timestamp ngoài cùng là thời gian thu từ UART ở tốc độ 115200 baud. Với
giai đoạn kernel, timestamp bên trong dấu `[]` được ưu tiên vì đó là thời gian
kernel đo trực tiếp.

## 2. Kết quả tổng quan

| Chỉ số | Trước tối ưu | Sau tối ưu | Thay đổi |
|---|---:|---:|---:|
| Ramdisk trong FIT | 9,882,602 B | 1,802,946 B | giảm 8,079,656 B (81.76%) |
| SPL đến màn hình login | 33.439 s | 11.331 s | giảm 22.108 s (66.11%) |
| RAM được giữ cho initrd | 9,648 KiB | 1,760 KiB | giảm 7,888 KiB |
| RAM available | 1,003,664 KiB | 1,011,552 KiB | tăng 7,888 KiB |

Kernel không thay đổi: cả hai bản đều có kích thước `3,281,717` byte và cùng
SHA-256 bắt đầu bằng `936016b7`. Vì vậy kết quả hiện tại chủ yếu đến từ U-Boot,
ramdisk/rootfs và dịch vụ userspace, không đến từ tối ưu kernel binary.

## 3. Phân rã thời gian boot

| Giai đoạn | Trước | Sau | Thời gian giảm | Nguyên nhân chính |
|---|---:|---:|---:|---|
| SPL đến U-Boot proper | 0.601 s | 0.621 s | -0.020 s | Không được tối ưu; sai số giữa các lần chạy |
| U-Boot đến bắt đầu đọc FIT | 5.273 s | 0.250 s | 5.023 s | `CONFIG_BOOTDELAY=5` đổi thành `0` |
| Bắt đầu đọc FIT đến start kernel | 10.481 s | 5.111 s | 5.370 s | Ramdisk nhỏ làm hash và relocate nhanh hơn |
| Start kernel đến chạy `/init` | 8.777 s | 3.590 s | 5.187 s | Kernel giải nén/extract initramfs nhỏ hơn |
| Chạy `/init` đến login | 8.307 s | 1.759 s | 6.548 s | Không còn khởi động OpenSSH và chờ entropy |
| **Tổng** | **33.439 s** | **11.331 s** | **22.108 s** | |

Phần giảm 22.108 giây được phân bổ xấp xỉ như sau:

| Nguồn cải thiện | Thời gian |
|---|---:|
| Bỏ bootdelay | 5.023 s |
| U-Boot xử lý ramdisk nhỏ hơn | 5.370 s |
| Kernel unpack initramfs nhỏ hơn | 5.187 s |
| Bỏ OpenSSH và thời gian chờ entropy | 6.548 s |
| Dao động SPL/OpenSBI | -0.020 s |

Nếu loại phần `BOOTDELAY=0`, hệ thống vẫn nhanh hơn khoảng `17.085` giây.

## 4. Nguyên nhân thay đổi theo từng giai đoạn

### 4.1. SPL và OpenSBI

```text
Trước: 17:48:18.655349 -> 17:48:19.256348 = 0.600999 s
Sau:   18:35:19.135941 -> 18:35:19.756805 = 0.620864 s
```

Hai lần boot đều dùng OpenSBI v1.7, firmware 317 KiB, một HART và cùng đường
khởi động qua DDR. Rootfs chưa được xử lý ở đây. Chênh lệch khoảng 20 ms có thể
do UART và dao động giữa hai lần đo, không phải ảnh hưởng của tối ưu rootfs.

### 4.2. U-Boot initialization và autoboot

```text
Trước: U-Boot 19.256348 -> FIT 24.529070 = 5.272722 s
Sau:   U-Boot 19.756805 -> FIT 20.006642 = 0.249837 s
Giảm:                                      5.022885 s
```

Bản trước đếm autoboot từ 5 về 0. Bản sau dùng `CONFIG_BOOTDELAY=0` nên chuyển
gần như ngay sang lệnh boot. Phần cải thiện này không liên quan đến dung lượng
FIT hoặc rootfs.

`configs/genesys2/uboot64_defconfig` hiện có cả `CONFIG_BOOTDELAY=5` và
`CONFIG_BOOTDELAY=0`; giá trị xuất hiện sau cùng có hiệu lực. Nên chỉ giữ một
giá trị để tránh nhầm lẫn khi bảo trì.

### 4.3. Xác minh kernel trong FIT

| Thuộc tính | Trước | Sau |
|---|---:|---:|
| Kích thước kernel gzip | 3,281,717 B | 3,281,717 B |
| Thời gian SHA-256 | 1.066546 s | 1.065034 s |

Kernel có cùng kích thước và cùng hash. Chênh lệch 1.5 ms là không đáng kể và
xác nhận kernel chưa đóng góp vào phần giảm thời gian.

### 4.4. Xác minh ramdisk trong FIT

```text
Trước: 27.689442 -> 32.915875 = 5.226433 s
Sau:   23.165751 -> 23.299538 = 0.133787 s
Giảm:                               5.092646 s
```

Ramdisk giảm từ `9,882,602` xuống `1,802,946` byte. U-Boot phải đọc toàn bộ
payload để tính SHA-256, nên giảm 81.76% dữ liệu đã làm giảm mạnh thời gian hash.

Ramdisk nhỏ hơn do đã loại các package không cần cho cấu hình UART tối thiểu,
gồm OpenSSH, iproute2, tcpdump, ethtool, iperf3, util-linux, libgpiod tools,
các benchmark và dependency không còn được sử dụng. OpenSSH/OpenSSL và
iproute2 là các thành phần lớn trong nhóm này.

### 4.5. Xác minh Device Tree

```text
Trước: 10,189 B
Sau:   10,245 B
```

DTB tăng 56 byte và việc xác minh chỉ mất vài mili giây. DTB không tạo ra phần
cải thiện đáng kể. Hash DTB thay đổi chứng minh hai lần boot không dùng cùng
một DTB.

### 4.6. Giải nén kernel và relocate ramdisk

```text
Trước: Uncompress kernel 32.975617 -> start kernel 35.010012 = 2.034395 s
Sau:   Uncompress kernel 23.358696 -> start kernel 25.117606 = 1.758910 s
Giảm:                                                        0.275485 s
```

Kernel gzip giống hệt nhau nên thời gian giải nén kernel không phải nguyên
nhân chính. Khoảng giảm 0.275 giây nhiều khả năng đến từ việc U-Boot copy hoặc
relocate ramdisk 1.80 MB thay vì 9.88 MB. Log chỉ cung cấp mốc tổng hợp nên
không thể tách tuyệt đối thời gian kernel decompression và ramdisk relocation.

### 4.7. Kernel initialization trước initramfs

```text
Trước: [0.459500] Unpacking initramfs...
Sau:   [0.459610] Unpacking initramfs...
```

Thời điểm bắt đầu unpack chỉ khác 0.000110 giây. Điều này phù hợp với việc
kernel binary và hầu hết quá trình khởi tạo kernel không thay đổi. Việc bỏ
package userspace không làm nhanh hơn giai đoạn này.

### 4.8. Kernel unpack initramfs

```text
Trước: [0.459500] -> [7.735780] = 7.276280 s
Sau:   [0.459610] -> [2.548340] = 2.088730 s
Giảm:                              5.187550 s
```

Ở giai đoạn này kernel phải:

1. Giải nén gzip của `rootfs.cpio.gz`.
2. Parse các CPIO entry.
3. Tạo inode, dentry và thư mục.
4. Copy nội dung từng file vào initramfs.
5. Cấp phát page cho dữ liệu rootfs.

Rootfs nhỏ hơn làm giảm cả lượng dữ liệu lẫn số file cần xử lý. Trong bản cũ,
các bước khởi tạo driver gần như hoàn tất tại `[2.136310]` nhưng kernel vẫn chờ
initramfs đến `[7.735780]`. Bản mới hoàn tất các bước tương ứng tại khoảng
`[2.171460]` và initramfs kết thúc tại `[2.548340]`.

### 4.9. Các init script chung

| Công việc | Trước | Sau | Nhận xét |
|---|---:|---:|---|
| `/init` đến lưu random seed | 0.707 s | 0.699 s | Gần như không đổi |
| Start `syslogd` | 0.060 s | 0.060 s | Không đổi |
| Start `klogd` | 0.040 s | 0.040 s | Không đổi |
| Run `sysctl` | 0.280 s | 0.280 s | Không đổi |

BusyBox init, syslog, klog và sysctl không đóng góp đáng kể vào phần cải thiện.

### 4.10. Network initialization

```text
Trước: sysctl -> network OK   = khoảng 0.460 s
Sau:   sysctl -> network FAIL = khoảng 0.440 s
```

Chênh lệch khoảng 20 ms không phải là tối ưu hợp lệ. Bản mới báo:

```text
/bin/sh: ip: not found
FAIL
```

`iproute2` đã bị loại nhưng script `S40network` vẫn gọi lệnh `ip`. Nếu image
chỉ dùng UART, có thể tắt `BR2_PACKAGE_IFUPDOWN_SCRIPTS`. Nếu vẫn cần network,
cần cài lại applet `ip` của BusyBox hoặc bật lại `iproute2`.

### 4.11. OpenSSH và thời gian đến login

Bản trước:

```text
45.433733 Starting crond: OK
50.898893 random: crng init done
51.893698 Starting sshd: OK
52.094655 Welcome to Buildroot
```

Bản sau:

```text
30.286524 Starting crond: OK
30.467366 Welcome to Buildroot
```

Thời gian từ `crond` đến login:

```text
Trước: 6.660922 s
Sau:   0.180842 s
Giảm:  6.480080 s
```

Nguyên nhân chính là OpenSSH đã bị loại bỏ. Bản trước phải chờ CRNG sẵn sàng
rồi hoàn tất khởi động `sshd`; bản mới chuyển gần như ngay sang getty/login.
Đây vừa là cải thiện hiệu năng vừa là thay đổi chức năng: image mới không còn
SSH server.

## 5. Regression và vấn đề cần xử lý

### 5.1. Network script thất bại

```text
Starting network: /bin/sh: ip: not found
/bin/sh: ip: not found
FAIL
```

Không nên tính phần này là thành quả tối ưu. Cần thống nhất một trong hai hướng:

- image chỉ dùng UART: tắt startup script network;
- image cần network: cung cấp lại lệnh `ip` và kiểm tra interface thực tế.

### 5.2. PLIC báo context CPU không hợp lệ

```text
riscv-plic: interrupt-controller@c000000: Invalid cpuid for context 3
```

DTB mới mô tả bốn PLIC context trong khi OpenSBI chỉ công bố một HART và CPU1
đang disabled. Cảnh báo chưa ngăn hệ thống boot nhưng cần sửa DTB để chỉ tham
chiếu context của HART hợp lệ.

### 5.3. Không còn SSH

Việc bỏ OpenSSH giúp giảm cả dung lượng và thời gian boot, nhưng đồng thời loại
bỏ khả năng đăng nhập từ xa. Đây là kết quả đúng nếu mục tiêu là rootfs UART
tối thiểu; nếu sản phẩm cần quản trị qua mạng thì phải đánh giá lại.

## 6. Kết luận

Bản optimized giảm tổng thời gian boot từ `33.439` xuống `11.331` giây. Trong
đó khoảng 5.023 giây đến từ bỏ bootdelay, khoảng 10.56 giây đến trực tiếp từ
ramdisk nhỏ hơn ở U-Boot và kernel, và khoảng 6.55 giây đến từ việc bỏ các bước
userspace, chủ yếu là OpenSSH.

Kết quả tối ưu rootfs là rõ ràng, nhưng trước khi coi image hoàn chỉnh cần xử
lý lỗi thiếu lệnh `ip`, cảnh báo PLIC trong DTB và xác nhận việc loại bỏ SSH là
phù hợp với yêu cầu sản phẩm.

## 7. Lệnh kiểm tra lại số liệu

```bash
# Xem các mốc boot chính
rg -n 'U-Boot SPL|U-Boot 20|Loading kernel|Data Size|Verifying Hash|Starting kernel|Unpacking initramfs|Freeing initrd|Run /init|Starting network|Starting sshd|Welcome' \
  log_1609_timesptamp log_fullflow_optimized

# Kiểm tra kernel có giống nhau không
rg -n 'Data Size:.*3.1 MiB|936016b7' \
  log_1609_timesptamp log_fullflow_optimized

# Kiểm tra cấu hình bootdelay
rg -n '^CONFIG_BOOTDELAY=' configs/genesys2/uboot64_defconfig

# Kiểm tra các package đã tắt
rg -n '^#BR2_PACKAGE_.*=y bo$' configs/genesys2/buildroot64_defconfig

# Kiểm tra lỗi hoặc cảnh báo mới
rg -n 'FAIL|not found|Invalid cpuid|error|warning' log_fullflow_optimized
```
