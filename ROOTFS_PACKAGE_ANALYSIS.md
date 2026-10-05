# Phân tích và tối ưu package trong rootfs Genesys2 64-bit

## 1. Mục tiêu

Tài liệu này ghi lại các package từng được bật trong
`configs/genesys2/buildroot64_defconfig`, công dụng, dependency và lý do tắt
chúng để tạo rootfs tối thiểu dùng cho boot và đăng nhập qua UART.

Các package bị tắt vẫn được giữ lại trong defconfig dưới dạng comment và có
nhãn `bo`, ví dụ:

```text
#BR2_PACKAGE_OPENSSH=y bo
```

## 2. Kết quả giảm dung lượng

| Artifact | Trước khi tối ưu | Sau khi tối ưu |
|---|---:|---:|
| `rootfs.cpio.gz` | 9,882,641 byte | 1,802,941 byte |
| `fitImage.itb` | 13,175,836 byte | 5,096,136 byte |

`fitImage.itb` giảm khoảng 8.08 MB, tương đương 61.3%.

Image sau khi tối ưu vẫn chứa các thành phần cần thiết để boot qua UART:

- `/init`
- BusyBox
- `/bin/sh`
- `/sbin/init`
- `/sbin/getty`
- `/etc/inittab`
- `/etc/init.d/rcS`
- glibc và dynamic loader

## 3. Danh sách package đã tắt

Dung lượng trong bảng là dung lượng chưa nén đo từ rootfs trước khi tối ưu.

| Package/option | Công dụng | Dependency chính | Dung lượng cũ | Đánh giá |
|---|---|---|---:|---|
| `BR2_PACKAGE_DHRYSTONE` | Benchmark hiệu năng xử lý số nguyên của CPU | libc, toolchain | 10 KB | Không cần để boot; chỉ giữ khi benchmark CPU |
| `BR2_PACKAGE_MEMSTAT` | Liệt kê process, executable và shared library đang sử dụng bộ nhớ ảo | libc | 14 KB | Công cụ debug tùy chọn |
| `BR2_PACKAGE_LIBGPIOD2` | Thư viện truy cập GPIO qua character device của Linux | Kernel headers >= 5.10, `CONFIG_GPIO_CDEV` | 34 KB | Hiện chưa hữu ích vì kernel chưa bật `CONFIG_GPIO_SIFIVE` |
| `BR2_PACKAGE_LIBGPIOD2_TOOLS` | Cài `gpiodetect`, `gpioinfo`, `gpioget`, `gpioset`, `gpiomon`, `gpionotify` | `libgpiod2.so` | Tổng library và tools: 190 KB | Chỉ cần khi GPIO driver hoạt động |
| `BR2_PACKAGE_ETHTOOL` | Đọc/chỉnh trạng thái link, PHY, statistics và register Ethernet | libc, Ethernet driver trong kernel | 741 KB | Chỉ cần khi debug Ethernet |
| `BR2_PACKAGE_IPERF3` | Đo bandwidth TCP/UDP | `libiperf.so`; dùng OpenSSL nếu OpenSSL đang bật | 203 KB | Chỉ cần benchmark mạng |
| `BR2_PACKAGE_IPROUTE2` | Cung cấp `ip`, `ss`, `tc`, `bridge`, `nstat` và các công cụ mạng nâng cao | libc, kernel netlink | 2.10 MB | BusyBox đã có `ip`, `ifconfig`, `route`, `netstat` cho nhu cầu cơ bản |
| `BR2_PACKAGE_OPENSSH` | SSH client/server, SCP, SFTP và key utilities | OpenSSL, zlib; server dùng libxcrypt với glibc | 6.06 MB | Không cần cho cấu hình chỉ dùng UART |
| `BR2_PACKAGE_TCPDUMP` | Bắt và phân tích packet mạng | libpcap | 1.22 MB | Chỉ cần debug mạng |
| `BR2_PACKAGE_UTIL_LINUX` | Framework chứa nhiều utility và library Linux | Tùy component được chọn | 839 KB | Cấu hình cũ chủ yếu chỉ cài library; BusyBox cung cấp lệnh cơ bản |
| `BR2_PACKAGE_UTIL_LINUX_LIBMOUNT` | Parse mount table, filesystem và mount options | libblkid | 437 KB | Không có executable hiện tại sử dụng |
| `BR2_PACKAGE_UTIL_LINUX_LIBUUID` | Xử lý UUID | libc | 31 KB | Không có executable hiện tại sử dụng |
| `BR2_PACKAGE_VITETRIS` | Game Tetris chạy trên terminal | libc | 113 KB | Demo, không cần cho hệ thống |
| `BR2_PACKAGE_CACHETEST` | Benchmark cache với nhiều working-set/stride, đọc CSR `cycle` và `instret` | libc, CPU RISC-V hỗ trợ các CSR tương ứng | 6 KB | Chỉ cần khi kiểm tra CPU/cache |

## 4. Quan hệ dependency

```text
OpenSSH
├── OpenSSL
│   ├── libcrypto.so
│   └── libssl.so
├── zlib
└── libxcrypt (SSH server khi dùng glibc)

iperf3
├── libiperf.so
└── OpenSSL (chỉ khi OpenSSL đã được bật bởi package khác)

tcpdump
└── libpcap

libgpiod2 tools
└── libgpiod2.so

util-linux libmount
└── libblkid
```

Các dependency gián tiếp lớn từng có trong rootfs:

| Dependency | Dung lượng cũ | Package sử dụng |
|---|---:|---|
| OpenSSL | 5.54 MB | OpenSSH; iperf3 sử dụng nếu có |
| libpcap | 260 KB | tcpdump |
| libblkid | 371 KB | util-linux libmount |
| libxcrypt | 223 KB | OpenSSH server/util-linux trong cấu hình cũ |
| zlib | 84 KB | OpenSSH/util-linux trong cấu hình cũ |

Các dependency trên được Buildroot tự động tắt khi không còn package nào cần
chúng; vì vậy chúng không có dòng `bo` riêng trong defconfig.

## 5. Lý do nhóm package mạng được tắt

DTB đang được đóng trong `fitImage.itb` không chứa node Ethernet
`lowrisc-eth`. Boot log cũng không cho thấy Linux probe được `eth0`, và
`/etc/network/interfaces` chỉ cấu hình loopback.

Do chưa có network interface hoạt động, các package sau chưa sử dụng được:

- OpenSSH
- iperf3
- iproute2
- tcpdump
- ethtool

Nếu sửa DTB và driver Ethernet trong tương lai, có thể bật lại những package
thực sự cần. Không nhất thiết phải bật lại toàn bộ nhóm.

## 6. GPIO

DTB thực tế có node GPIO tương thích SiFive và kernel có GPIO character
device, nhưng cấu hình kernel hiện tại có:

```text
# CONFIG_GPIO_SIFIVE is not set
```

Vì vậy các công cụ libgpiod chưa thể truy cập GPIO controller này. Trước khi
bật lại `LIBGPIOD2_TOOLS`, cần bật driver GPIO SiFive và xác nhận xuất hiện
`/dev/gpiochip*`.

## 7. Các package cần giữ cho rootfs UART tối thiểu

Dung lượng trong bảng là dung lượng chưa nén được ghi nhận trong rootfs.

| Package/option | Công dụng | Dependency chính | Dung lượng | Lý do giữ |
|---|---|---|---:|---|
| `BR2_PACKAGE_BUSYBOX` | Cung cấp shell và phần lớn lệnh userspace như `mount`, `getty`, `devmem`, `hostname`, `ip` và `sleep` | glibc, dynamic loader, `libresolv` | 778 KB | Thành phần userspace chính; cần cho init script, shell và đăng nhập UART |
| glibc/toolchain runtime | Cung cấp `libc.so`, dynamic loader, `libm`, `libresolv` và các thư viện C nền | RISC-V toolchain | 2.32 MB | Mọi executable dynamic trong rootfs cần libc và dynamic loader |
| GCC runtime | Cung cấp `libgcc_s` và `libatomic` cho executable được cross-compile | glibc, GCC toolchain | 23 KB | Hỗ trợ các phép toán/runtime mà compiler không triển khai trực tiếp trong executable |
| `BR2_PACKAGE_SKELETON_INIT_SYSV` | Tạo cấu trúc filesystem và cấu hình nền cho hệ thống SysV | Không có dependency target lớn | Khoảng 334 byte được attribution trực tiếp | Cung cấp skeleton cần thiết để Buildroot tạo rootfs SysV hợp lệ |
| `BR2_PACKAGE_INITSCRIPTS` | Cung cấp `rcS`, `rcK` và script nạp module | BusyBox shell, skeleton SysV | 1.8 KB | Khởi chạy các service khi boot và dừng service khi shutdown |
| `BR2_PACKAGE_URANDOM_SCRIPTS` | Lưu và nạp random seed qua script `S01seedrng` | BusyBox, kernel random subsystem | 1.2 KB | Khởi tạo entropy userspace ổn định hơn sau khi boot |
| `BR2_PACKAGE_IFUPDOWN_SCRIPTS` | Cung cấp `S40network` và `/etc/network/interfaces` | BusyBox networking applets | 1.9 KB | Thiết lập interface loopback; có thể bỏ nếu không cần networking dưới mọi hình thức |
| `BR2_TARGET_ROOTFS_CPIO` | Đóng filesystem thành initramfs CPIO | host-cpio | Không phải payload riêng | Kernel cần archive này làm root filesystem ban đầu |
| `BR2_TARGET_ROOTFS_CPIO_GZIP` | Nén `rootfs.cpio` thành `rootfs.cpio.gz` | host-gzip; kernel `CONFIG_RD_GZIP` | Giảm CPIO xuống khoảng 1.80 MB | Giảm kích thước FIT và vẫn được kernel hiện tại hỗ trợ |

BusyBox hiện cung cấp các lệnh cần cho boot và script debug, gồm `mount`,
`swapon`, `hostname`, `getty`, `devmem`, `sleep`, `usleep`, `cat`, `sh` và
`printf`.

## 8. Package chạy trên host

Các package có tiền tố `BR2_PACKAGE_HOST_` chạy trên máy build, không được
đưa vào rootfs và không làm tăng kích thước `fitImage.itb`:

- `BR2_PACKAGE_HOST_DOSFSTOOLS`
- `BR2_PACKAGE_HOST_GENIMAGE`
- `BR2_PACKAGE_HOST_MTOOLS`
- `BR2_PACKAGE_HOST_UBOOT_TOOLS`
- `BR2_PACKAGE_HOST_UBOOT_TOOLS_FIT_SUPPORT`
- `BR2_PACKAGE_HOST_GDB`

Các package host phục vụ tạo filesystem, SD image, FIT image và debug nên vẫn
được giữ nguyên.

## 9. SSH key và `permission_table.txt`

Trước đây overlay chứa sáu SSH host key. `permission_table.txt` đặt mode `644`
cho public key và `600` cho private key.

Khi OpenSSH bị tắt, các key được bỏ khỏi overlay. Các entry tương ứng trong
`permission_table.txt` cũng phải bị vô hiệu hóa; nếu không, bước `makedevs`
sẽ thất bại vì cố đặt permission cho file không tồn tại.

Nếu bật lại OpenSSH, nên tạo host key riêng cho từng board thay vì nhúng cùng
một private key vào mọi firmware.

## 10. Cách bật lại package

Ví dụ dòng đang bị tắt:

```text
#BR2_PACKAGE_OPENSSH=y bo
```

Để bật lại, phải xóa cả dấu `#` và chữ `bo`:

```text
BR2_PACKAGE_OPENSSH=y
```

Sau đó chạy lại Buildroot. Với OpenSSH, cần đồng thời cấu hình cách tạo SSH
host key và cập nhật `permission_table.txt` nếu key được cung cấp từ overlay.

Khi thay đổi danh sách package, nên clean/rebuild rootfs để tránh file của
package đã tắt còn sót lại trong `output/target`.

## 11. Các lệnh kiểm tra

Chạy các lệnh dưới đây từ thư mục gốc của repository `cva6-sdk`.

### 11.1. Kiểm tra package trong defconfig

Liệt kê toàn bộ package target và host được khai báo trực tiếp:

```bash
rg -n '^#?BR2_PACKAGE_[A-Z0-9_]+(=y|=y bo)$' \
  configs/genesys2/buildroot64_defconfig
```

Kiểm tra các package đang thực sự được bật trong cấu hình Buildroot đã sinh:

```bash
rg -n '^BR2_PACKAGE_[A-Z0-9_]+=y' buildroot/.config
```

Kiểm tra riêng các package đã tắt để giảm rootfs:

```bash
rg -n '^#BR2_PACKAGE_.*=y bo$' \
  configs/genesys2/buildroot64_defconfig
```

### 11.2. Kiểm tra dependency package

Dependency trực tiếp của một package:

```bash
make -s -C buildroot openssh-show-depends
make -s -C buildroot iperf3-show-depends
make -s -C buildroot tcpdump-show-depends
make -s -C buildroot util-linux-show-depends
```

Package nào phụ thuộc vào một library:

```bash
make -s -C buildroot openssl-show-rdepends
make -s -C buildroot libpcap-show-rdepends
make -s -C buildroot libxcrypt-show-rdepends
make -s -C buildroot zlib-show-rdepends
```

Kiểm tra nhiều package cùng lúc:

```bash
for package_name in \
  openssh ethtool iperf3 iproute2 tcpdump util-linux libgpiod2 \
  dhrystone memstat vitetris cachetest
do
  printf '%s: ' "$package_name"
  make -s -C buildroot "${package_name}-show-depends"
done
```

Kết quả dependency phụ thuộc vào `.config` đang active. Ví dụ iperf3 chỉ hiện
dependency OpenSSL khi OpenSSL đang được bật.

### 11.3. Thống kê dung lượng theo package

Tạo báo cáo dung lượng từ rootfs hiện tại:

```bash
make -C buildroot graph-size
```

Các file kết quả:

```text
buildroot/output/graphs/package-size-stats.csv
buildroot/output/graphs/file-size-stats.csv
buildroot/output/graphs/graph-size.pdf
```

Xếp package theo dung lượng giảm dần:

```bash
sort -t, -k2,2nr buildroot/output/graphs/package-size-stats.csv | head -n 30
```

Liệt kê các file lớn nhất trong target:

```bash
find buildroot/output/target -xdev -type f -printf '%s %p\n' \
  | sort -nr \
  | head -n 60
```

Đo tổng dung lượng target và các artifact:

```bash
du -sb buildroot/output/target
stat -c '%n %s bytes' \
  install64_genesys2/rootfs.cpio \
  install64_genesys2/rootfs.cpio.gz \
  install64_genesys2/fitImage.itb
```

Xem tỷ lệ nén của rootfs:

```bash
gzip -l install64_genesys2/rootfs.cpio.gz
```

### 11.4. Kiểm tra nội dung rootfs

Liệt kê toàn bộ nội dung initramfs mà không cần giải nén ra thư mục:

```bash
gzip -dc install64_genesys2/rootfs.cpio.gz | cpio -it
```

Kiểm tra các file boot quan trọng:

```bash
gzip -dc install64_genesys2/rootfs.cpio.gz \
  | cpio -it 2>/dev/null \
  | rg '^(init|linuxrc|bin/(busybox|sh)|sbin/(init|getty)|etc/inittab|etc/init.d/rcS)$'
```

Kiểm tra package đã bỏ có còn sót trong archive không:

```bash
gzip -dc install64_genesys2/rootfs.cpio.gz \
  | cpio -it 2>/dev/null \
  | rg '(^|/)(sshd|ssh$|iperf3|tcpdump|ethtool|tetris|cachetest\.elf|dhrystone|memstat|libcrypto\.so|libssl\.so|libpcap\.so|libgpiod\.so|libmount\.so|libblkid\.so)'
```

Nếu lệnh trên không in ra kết quả thì các payload đã được loại khỏi archive.

Kiểm tra tính toàn vẹn của gzip:

```bash
gzip -t install64_genesys2/rootfs.cpio.gz && echo 'gzip test: OK'
```

### 11.5. Kiểm tra thư viện runtime

Xem shared library mà BusyBox cần:

```bash
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-readelf \
  -d buildroot/output/target/bin/busybox \
  | rg 'NEEDED'
```

Kiểm tra symlink library bị gãy:

```bash
find buildroot/output/target/lib buildroot/output/target/usr/lib \
  -xtype l -print
```

Không có output nghĩa là không tìm thấy symlink library bị gãy.

### 11.6. Kiểm tra FIT image

Hiển thị kernel, DTB, ramdisk, địa chỉ load và hash trong FIT:

```bash
buildroot/output/host/bin/dumpimage -l \
  install64_genesys2/fitImage.itb
```

Kiểm tra file nào được template FIT đưa vào làm ramdisk:

```bash
rg -n 'rootfs\.cpio' fitImage.its fitImage.its.template
```

### 11.7. Kiểm tra DTB thực tế trong FIT

Liệt kê node Ethernet và GPIO trong DTB đang được đóng gói:

```bash
buildroot/output/host/bin/dtc \
  -I dtb -O dts install64_genesys2/u-boot.dtb 2>/dev/null \
  | rg -n 'lowrisc|ethernet|gpio|30000000|40000000'
```

In toàn bộ DTB dạng DTS để kiểm tra thủ công:

```bash
buildroot/output/host/bin/dtc \
  -I dtb -O dts install64_genesys2/u-boot.dtb
```

### 11.8. Kiểm tra cấu hình kernel liên quan

Kiểm tra driver Ethernet LowRISC:

```bash
rg -n 'CONFIG_(NET_VENDOR_LOWRISC|LOWRISC_DIGILENT_100MHZ)' \
  buildroot/output/build/linux-6.19.6/.config \
  configs/genesys2/linux64_defconfig
```

Kiểm tra GPIO character device và GPIO SiFive:

```bash
rg -n 'CONFIG_(GPIOLIB|GPIO_CDEV|GPIO_SIFIVE)' \
  buildroot/output/build/linux-6.19.6/.config \
  configs/genesys2/linux64_defconfig
```

Kiểm tra kernel hỗ trợ giải nén initramfs gzip:

```bash
rg -n 'CONFIG_RD_GZIP' buildroot/output/build/linux-6.19.6/.config
```

### 11.9. Kiểm tra boot log

Tìm quá trình khởi tạo Ethernet, SSH và network interface:

```bash
rg -ni 'lowrisc|ethernet|eth0|link is|network|sshd' log_1609
```

Tìm quá trình kernel chạy init và giải phóng initrd:

```bash
rg -n 'Freeing initrd|Run /init|Starting kernel|Welcome to Buildroot' \
  log_1609
```

### 11.10. Kiểm tra source và build

Kiểm tra shell script tạo FIT:

```bash
sh -n post_image.sh
```

Kiểm tra whitespace/error trong các file đã chỉnh:

```bash
git diff --check -- \
  configs/genesys2/buildroot64_defconfig \
  permission_table.txt \
  ROOTFS_PACKAGE_ANALYSIS.md
```

Tạo lại `.config` từ defconfig:

```bash
make -C buildroot \
  BR2_EXTERNAL="../br2-ext-tree" \
  BR2_DEFCONFIG=../configs/genesys2/buildroot64_defconfig \
  defconfig
```

Build image Genesys2 64-bit:

```bash
make -j4 XLEN=64 BOARD=genesys2
```

Sau khi build, chạy lại các kiểm tra gzip, CPIO và `dumpimage` ở trên.
