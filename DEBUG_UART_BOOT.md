# Debug Linux boot trap trên CVA6 / Genesys2

## 1. Hiện tượng

U-Boot nạp và kiểm tra hợp lệ FIT image thành công:

- Kernel gzip được giải nén tới `0x82800000`.
- Ramdisk và DTB được nạp thành công.
- Log kết thúc ở `Starting kernel ...`.

Sau khi halt bằng OpenOCD, các thanh ghi là:

```text
pc     = 0x000000008001baba
mcause = 0x0000000000000002
mtvec  = 0x00000000800003c8
mepc   = 0xffffffff803cb86a
mtval  = 0x00000000c01027f3
sp     = 0x0000000080044d10
ra     = 0x000000008001bb4a
```

`mcause = 2` là **Illegal instruction**.

## 2. Kết luận

Lỗi phát sinh trong **Linux kernel**, không phải trong U-Boot và cũng không nằm ở
`do_bootm_vxworks`.

`mepc` phải được đọc đủ 64 bit:

```text
0xffffffff803cb86a
```

Đây là địa chỉ virtual của Linux kernel trong không gian Sv39. Bỏ phần
`0xffffffff` rồi so sánh `0x803cb86a` với địa chỉ physical/link address của
U-Boot là không chính xác.

Symbol map và disassembly của `vmlinux` xác nhận:

```text
ffffffff803cb84c <__delay>:
ffffffff803cb854: c0102773  rdtime a4
ffffffff803cb858: c01027f3  rdtime a5
...
ffffffff803cb86a: c01027f3  rdtime a5   <-- mepc
```

Do đó Linux đang thực hiện `rdtime a5` trong `__delay`, và lệnh này trap với
illegal instruction.

`pc = 0x8001baba` là địa chỉ khi OpenOCD dừng CPU **sau trap**. Nó nằm trong
OpenSBI (M-mode trap handler); việc này khớp với `mtvec = 0x800003c8`. Nó không
phải địa chỉ gây lỗi. Địa chỉ gây lỗi là `mepc`.

Luồng thực thi:

```text
U-Boot bootm Linux
  -> Linux S-mode chạy __delay()
  -> rdtime
  -> Illegal instruction (mcause = 2)
  -> OpenSBI M-mode handler tại mtvec
  -> OpenOCD halt, nên PC hiện tại ở OpenSBI
```

## 3. Phân biệt các image theo địa chỉ

| Thành phần | Địa chỉ/ý nghĩa quan sát được |
|---|---|
| OpenSBI `fw_dynamic` | nạp tại `0x80000000`; PC `0x8001baba` nằm trong firmware này |
| U-Boot proper | link từ `0x80200000`; `System.map` hiện tại kết thúc BSS tại `0x8027c1b0` |
| Linux | symbol virtual `ffffffff803cb84c` là `__delay` |
| Lệnh lỗi | `mepc = ffffffff803cb86a = __delay + 0x1e` |

FIT U-Boot cũng xác nhận layout:

```text
OpenSBI fw_dynamic: load 0x80000000
U-Boot:             load 0x80200000
```

## 4. Nguyên nhân kỹ thuật cần kiểm tra

`rdtime` đọc CSR `time` (`0xC01`). Với Linux chạy S-mode, lỗi này thường do một
trong các nguyên nhân sau:

1. CVA6 RTL không implement/không enable counter `time` (`Zicntr`).
2. CSR `mcounteren` không cho phép S-mode đọc time: bit `TM` (bit 1) bằng 0.
3. OpenSBI nhận diện privilege version cũ hoặc không ghi được `mcounteren`.
4. Device tree quảng cáo sai khả năng/tần số timer so với RTL.

OpenSBI 1.7 trong build hiện tại có code cố gắng enable toàn bộ counter cho
S-mode bằng `csr_write(CSR_MCOUNTEREN, -1)` khi privilege version >= 1.10.
Vì vậy cần kiểm tra cả cấu hình RTL lẫn giá trị CSR thực tế.

## 5. Các lệnh OpenOCD nên chạy khi CPU đang halt

```tcl
targets riscv.cpu0
halt
reg pc
reg mcause
reg mtvec
reg mepc
reg mtval
reg sp
reg ra

# Kiểm tra quyền truy cập counter và ISA thực tế
reg mstatus
reg mcounteren
reg scounteren
reg misa
```

Kỳ vọng `mcounteren` có bit 1 (`TM`) bật; thông thường giá trị là `0x7` hoặc
`0xffffffffffffffff`. Nếu bằng `0`, lệnh `rdtime` từ S-mode sẽ trap đúng như
log hiện tại.

## 6. Các lệnh đã dùng để đối chiếu image local

Chạy từ repository root:

```bash
# Cấu hình U-Boot/Linux và các file image
rg -n 'CONFIG_(RISCV|SYS_TEXT_BASE|SYS_SDRAM_BASE|OPENSBI|BOOTM|FIT|SPL)|riscv,isa|timebase-frequency|compatible' \
  buildroot/output/build/uboot-custom/.config \
  buildroot/output/build/linux-custom/.config \
  buildroot/output/build/uboot-custom/arch/riscv

find buildroot/output/build -maxdepth 3 -type f \
  \( -name vmlinux -o -name System.map -o -name '*.dtb' \)

# Map mepc tới symbol Linux
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-addr2line -f -i \
  -e buildroot/output/build/linux-6.19.6/vmlinux \
  0xffffffff803cb86a

# Disassemble vùng chứa mepc
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-objdump -d \
  --start-address=0xffffffff803cb830 \
  --stop-address=0xffffffff803cb890 \
  buildroot/output/build/linux-6.19.6/vmlinux

# Tìm symbol gần nhất của Linux
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-nm -n \
  buildroot/output/build/linux-6.19.6/vmlinux \
  | awk '$1 <= "ffffffff803cb86a" {last=$0} END {print last}'

# Kiểm tra U-Boot không có symbol tại 0x803cb86a
awk '$1 ~ /^[0-9a-fA-F]+$/ && ("0x" $1)+0 <= 0x803cb86a {last=$0} END {print last}' \
  buildroot/output/build/uboot-custom/System.map

# Xem địa chỉ section lúc link
readelf -SW buildroot/output/build/linux-6.19.6/vmlinux | awk '/\\.text/{print}'
readelf -SW buildroot/output/build/uboot-custom/u-boot | awk '/\\.text/{print}'

# Xem thành phần FIT U-Boot (OpenSBI và U-Boot proper)
buildroot/output/host/bin/mkimage -l buildroot/output/build/uboot-custom/u-boot.itb

# Đọc ISA và timer từ DTB U-Boot đang build
fdtget -t s buildroot/output/build/uboot-custom/dts/dt.dtb / compatible
fdtget -t s buildroot/output/build/uboot-custom/dts/dt.dtb /cpus/cpu@0 riscv,isa
fdtget -t i buildroot/output/build/uboot-custom/dts/dt.dtb /cpus/cpu@0 timebase-frequency

# Tìm cấu hình counter trong OpenSBI và Buildroot
rg -n 'mcounteren|scounteren|COUNTEREN' buildroot/output/build/opensbi-custom
rg -n 'BR2_TARGET_OPENSBI|BR2_RISCV_ISA|OPENSBI|CVA6' \
  buildroot/.config configs/genesys2/buildroot64_defconfig
```

Kết quả quan trọng của các lệnh trên:

```text
addr2line: __delay
nm Linux:  ffffffff803cb84c T __delay
objdump:   ffffffff803cb86a: c01027f3 rdtime a5
U-Boot:    .text bắt đầu 0x80200000; BSS kết thúc 0x8027c1b0
OpenSBI:   fw_dynamic được nạp tại 0x80000000
```

## 7. Mismatch Device Tree cần xử lý

Các source/config hiện không đồng nhất:

| Nguồn | `riscv,isa` / extensions | `timebase-frequency` |
|---|---|---|
| `configs/genesys2/cv64a6_imafdc_sv39.dts` | khai báo `zicntr`, `zihpm` | 25 MHz |
| DTB U-Boot build hiện tại | `rv64imafdczicsr_zifencei_zihpm` (không có `zicntr`) | 100 MHz |

Cần dùng một mô tả phần cứng đúng và nhất quán cho RTL, OpenSBI, U-Boot DTB và
DTB đưa vào FIT Linux:

- Nếu CVA6 có `time` CSR: enable `Zicntr`, bảo đảm OpenSBI cho phép S-mode đọc
  bằng `mcounteren.TM`, và khai báo `zicntr` trong DT.
- Nếu CVA6 không có `time` CSR: Linux RISC-V không thể dùng `rdtime` bình
  thường; cần enable counter trong RTL hoặc bổ sung firmware emulation phù hợp.
- Đặt `timebase-frequency` theo tần số CLINT thực tế (25 MHz hoặc 100 MHz sau
  khi xác nhận hardware), không theo giá trị đoán.

## 8. Các log không phải nguyên nhân crash

```text
No MMC device available
** Bad device specification mmc 0 **
Couldn't find partition mmc 0:2
```

Đây là boot script thử boot từ MMC trước. Sau đó U-Boot fallback sang FIT đã
được nạp sẵn tại `0x90000000`, kiểm hash thành công và bắt đầu boot kernel.
Chúng không phải nguyên nhân của trap `rdtime`.

## 9. Quy trình chạy lại: map symbol và disassemble một trap mới

Chạy từ repository root. Phải dùng `vmlinux` của **đúng build** đã tạo kernel
trong `fitImage.itb`; không dùng `Image`, `Image.gz` hay kernel của build cũ.

```bash
cd /data/workspaces/nguyenth/_repo/cva6-sdk
TOOLCHAIN=buildroot/output/host/bin/riscv64-buildroot-linux-gnu
VMLINUX=buildroot/output/build/linux-6.19.6/vmlinux
UBOOT_DIR=buildroot/output/build/uboot-custom

ls -l "$TOOLCHAIN-addr2line" "$TOOLCHAIN-objdump" "$TOOLCHAIN-nm"
file "$VMLINUX" "$UBOOT_DIR/u-boot"
```

### 9.1 Bước 1: lấy địa chỉ exception

Sau khi UART dừng ở `Starting kernel ...`, chạy trong OpenOCD:

```tcl
targets riscv.cpu0
halt
reg pc
reg mcause
reg mtvec
reg mepc
reg mtval
reg sp
reg ra
```

Copy giá trị **đủ 64 bit** vào shell. Không bỏ `ffffffff` ở đầu `mepc`:

```bash
MEPC=0xffffffff803cb86a   # thay bằng output của `reg mepc`
MTVAL=0x00000000c01027f3 # thay bằng output của `reg mtval`
```

`mepc` là lệnh gây exception nên luôn map nó. `pc` là nơi CPU đang dừng sau
trap; nó có thể là OpenSBI, không phải nơi lỗi. Với `mcause = 2`, `mtval`
thường là opcode của lệnh illegal.

### 9.2 Bước 2: `addr2line` — address thuộc function/source nào?

```bash
"$TOOLCHAIN-addr2line" -f -i -e "$VMLINUX" "$MEPC"
```

| Option | Ý nghĩa |
|---|---|
| `-e "$VMLINUX"` | ELF có symbol/debug information để tra |
| `-f` | in tên function |
| `-i` | in inline call chain nếu có |
| `"$MEPC"` | virtual address đầy đủ từ OpenOCD |

Output cho log hiện tại là:

```text
__delay
??:?
```

`??:?` chỉ có nghĩa image không có DWARF line-debug; `__delay` vẫn là symbol
hợp lệ. Nếu cả hai dòng đều `??`, dừng lại và kiểm tra lại `VMLINUX` có đúng
là image được đóng vào FIT đang nạp không.

### 9.3 Bước 3: `nm` — xác nhận symbol gần nhất và offset

```bash
"$TOOLCHAIN-nm" -n "$VMLINUX" \
  | awk -v addr="${MEPC#0x}" '$1 <= addr {last=$0} END {print last}'
```

`nm -n` sắp xếp symbol theo address; lệnh `awk` chọn symbol cuối cùng có
address nhỏ hơn hoặc bằng `mepc`. Với log này, kết quả là:

```text
ffffffff803cb84c T __delay
```

Tính offset trong function:

```bash
FUNCTION_START=0xffffffff803cb84c # cột đầu output của nm
printf 'offset inside function = 0x%x\n' $((MEPC - FUNCTION_START))
```

Kết quả `0x1e` nghĩa là `__delay + 0x1e`.

### 9.4 Bước 4: `objdump` — đọc lệnh assembly tại `mepc`

```bash
START=$(printf '0x%x' $((MEPC - 0x40)))
STOP=$(printf '0x%x' $((MEPC + 0x40)))
"$TOOLCHAIN-objdump" -d \
  --start-address="$START" --stop-address="$STOP" "$VMLINUX"
```

Tìm dòng có address bằng chính xác `mepc`, rồi so opcode với `mtval`. Output
của case này:

```text
ffffffff803cb854: c0102773  rdtime a4
ffffffff803cb858: c01027f3  rdtime a5
...
ffffffff803cb86a: c01027f3  rdtime a5
```

`mepc = ffffffff803cb86a` và `mtval = c01027f3` trùng dòng `rdtime a5`; đây là
xác nhận trực tiếp lỗi ở Linux `__delay`. RISC-V có lệnh 16-bit compressed và
32-bit normal, nên không tự cộng address theo 4: dùng address ở cột đầu objdump.

### 9.5 Bước 5: loại trừ U-Boot/OpenSBI

```bash
readelf -SW "$UBOOT_DIR/u-boot" | awk '/\.text/{print}'
awk -v addr="${MEPC#0x}" \
  '$1 ~ /^[0-9a-fA-F]+$/ && $1 <= addr {last=$0} END {print last}' \
  "$UBOOT_DIR/System.map"
buildroot/output/host/bin/mkimage -l "$UBOOT_DIR/u-boot.itb"
```

Trong build hiện tại, U-Boot `.text` bắt đầu ở `0x80200000`, `System.map` kết
thúc BSS ở `0x8027c1b0`; không có code U-Boot tại `0x803cb86a`. FIT nạp OpenSBI
tại `0x80000000`, nên `pc=0x8001baba` sau trap phù hợp với OpenSBI handler.

### 9.6 Bước 6: kiểm tra quyền đọc `time` counter

Trong OpenOCD, khi CPU đang halt:

```tcl
reg mstatus
reg mcounteren
reg scounteren
reg misa
```

```text
mcounteren bit 0 (CY): S-mode đọc cycle
mcounteren bit 1 (TM): S-mode đọc time / rdtime
mcounteren bit 2 (IR): S-mode đọc instret
```

Vì lệnh lỗi là `rdtime`, bit `TM` phải bằng 1. `mcounteren = 0x0` là sai;
`0x2`, `0x7`, hoặc `0xffffffffffffffff` đều cấp quyền đọc `time`. Nếu CSR
không đọc được, kiểm tra RTL CVA6 và RISC-V privilege version được implement.

### 9.7 Mẫu kết quả cần lưu sau mỗi lần debug

```text
FIT build timestamp/hash:
MEPC:
MTVAL:
MCAUSE:
PC sau halt:
addr2line output:
nm symbol gần nhất:
objdump dòng trùng MEPC:
mcounteren:
misa:
DTB riscv,isa và timebase-frequency:
```
