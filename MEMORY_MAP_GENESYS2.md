# Sơ đồ bộ nhớ boot CVA6 Genesys2 (RV64)

Tài liệu này được trích trực tiếp từ bộ build hiện tại ngày 2026-08-27 trong
`buildroot/output/build` và các image tương ứng trong `install64_genesys2`.
Mọi khoảng địa chỉ dùng dạng **`[start, end)`**: `start` được dùng, `end` là
địa chỉ byte đầu tiên không thuộc vùng.

Thư mục `1040_307_01_jumped_2_opensbi` là snapshot cũ ngày 2026-07-30, trong
đó SPL còn link tại `0x8000_0000`. Tài liệu này không dùng snapshot đó vì
binary hiện tại trong `buildroot/output/build/uboot-custom` khớp SHA-256 với
`install64_genesys2` và đã chuyển SPL sang OCM tại `0x0800_0000`.

## 1. Tổng quan theo giai đoạn boot

SPL chạy trong OCM, còn OpenSBI, U-Boot, Linux và NPU firmware chạy trong
DDR. Sơ đồ dưới đây không vẽ theo tỷ lệ.

```text
OCM
0x0800_0000  +----------------------------------+
             | SPL image + SPL control DTB      |
0x0800_D083  +----------------------------------+
             | trống                            |
0x0804_0000  +----------------------------------+
             | SPL .bss (0xA8 byte)             |
0x0804_00A8  +----------------------------------+
             | trống                            |
0x0804_BF00  +----------------------------------+
             | SPL global_data (gd_t), 0x100 B  |  gp/x3 = 0x0804_BF00
0x0804_C000  +----------------------------------+
             | early malloc arena, 64 KiB       |
0x0805_0000  | - - giới hạn BSS cấu hình - - -  |  overlap tiềm ẩn
0x0805_C000  +----------------------------------+
             | SPL stack reserve, 16 KiB        |  stack đi xuống
0x0806_0000  +----------------------------------+  CONFIG_SPL_STACK / stack top

DDR, base 0x8000_0000, size chính 0x4000_0000 (1 GiB theo DTB)
0x8000_0000  +----------------------------------+
             | OpenSBI code/RO/RW/BSS           |
0x8004_4000  +----------------------------------+  _fw_end của ELF
             | stack 2 hart                     |
0x8004_8000  +----------------------------------+
             | OpenSBI heap runtime             |
0x8005_2400  +----------------------------------+  firmware runtime end
             | trống                            |
0x8020_0000  +----------------------------------+
             | U-Boot proper                    |
0x8027_2B08  +----------------------------------+  _end / __bss_start
             | U-Boot .bss                      |
0x8027_C1B0  +----------------------------------+
             | trống                            |
0x804E_BEB0  +----------------------------------+
             | U-Boot proper initial gd_t       |  trước relocation
0x804E_C000  +----------------------------------+
             | U-Boot proper early malloc 64KiB |  trước relocation
0x804F_C000  +----------------------------------+
             | U-Boot proper initial stack 16KiB|  stack đi xuống
0x8050_0000  +----------------------------------+
             | SPL malloc arena, 8 MiB          |  chỉ tồn tại trong pha SPL
0x80D0_0000  +----------------------------------+
             | trống                            |
0x8280_0000  +----------------------------------+
             | Linux Image sau giải nén          |
0x834B_1A00  +----------------------------------+  cuối dữ liệu có trong Image
             | Linux .sbss/.bss                 |
0x834F_6000  +----------------------------------+  _end, căn trang
             | trống                            |
0x8400_0000  +----------------------------------+
             | vùng NPU firmware, 1 MiB         |  chưa reserve trong DTB
0x8410_0000  +----------------------------------+
             | trống                            |
0x9000_0000  +----------------------------------+
             | fitImage.itb staging (0xC71628)  |
0x90C7_1628  +----------------------------------+
```

Đường boot QSPI hiện đọc FIT theo từng đoạn và chép thẳng các subimage đến
địa chỉ `load` trong FIT; nó không copy nguyên `u-boot.itb` hay `NPU_fw.itb`
vào một vùng staging DDR. `CONFIG_SPL_LOAD_FIT_ADDRESS` của build mới bằng
`0`, vì vậy `0x8280_0000` chỉ còn là địa chỉ load/entry của Linux trong
`fitImage.itb`, không phải staging của `u-boot.itb`. Vùng U-Boot proper quanh
`0x8050_0000` trong sơ đồ trên chỉ là layout **trước relocation**; layout sau
relocation được trình bày riêng ở mục 4.

NPU source, ELF và FIT artifact hiện đã thống nhất tại `0x8400_0000`;
chi tiết kiểm tra nằm ở mục 6.

## 2. SPL trong OCM

Nguồn: `buildroot/output/build/uboot-custom/spl/u-boot-spl`,
`u-boot-spl.map`, `u-boot-spl.bin` và `.config`.

Entry point: **`0x0800_0000`**.

| Vùng | Start | End | Size |
|---|---:|---:|---:|
| `.text` | `0x0800_0000` | `0x0800_7528` | `0x7528` (29.29 KiB) |
| `.rodata` | `0x0800_7528` | `0x0800_9DE0` | `0x28B8` (10.18 KiB) |
| `.data` | `0x0800_9DE0` | `0x0800_BB38` | `0x1D58` (7.34 KiB) |
| `.got` | `0x0800_BB38` | `0x0800_BC88` | `0x150` |
| `.got.plt` | `0x0800_BC88` | `0x0800_BC98` | `0x10` |
| `__u_boot_list` | `0x0800_BC98` | `0x0800_C728` | `0xA90` |
| `.binman_sym_table` | `0x0800_C728` | `0x0800_C740` | `0x18` |
| SPL control DTB nối cuối binary | `0x0800_C740` | `0x0800_D083` | `0x943` (2,371 B) |
| `.bss` | `0x0804_0000` | `0x0804_00A8` | `0xA8` |
| `global_data` (`gd_t`) | `0x0804_BF00` | `0x0804_C000` | `0x100` (256 B) |
| early malloc (`SYS_MALLOC_F`) | `0x0804_C000` | `0x0805_C000` | `0x10000` (64 KiB) |
| stack SPL dự phòng | `0x0805_C000` | `0x0806_0000` | `0x4000` (16 KiB) |

Các giới hạn cấu hình:

| Cấu hình | Giá trị | Ý nghĩa |
|---|---:|---|
| `CONFIG_SPL_TEXT_BASE` | `0x0800_0000` | đầu SPL trong OCM |
| `CONFIG_SPL_MAX_SIZE` | `0x0004_0000` | SPL phải nằm trước `0x0804_0000` |
| `CONFIG_SPL_BSS_START_ADDR` | `0x0804_0000` | đầu BSS |
| `CONFIG_SPL_BSS_MAX_SIZE` | `0x0001_0000` | vùng BSS dự phòng đến `0x0805_0000` |
| `CONFIG_SPL_STACK` | `0x0806_0000` | đỉnh stack, stack tăng về địa chỉ thấp |
| `CONFIG_STACK_SIZE_SHIFT` | `14` | vùng stack là `1 << 14 = 0x4000` byte |
| `CONFIG_SPL_SYS_MALLOC_F_LEN` | `0x0001_0000` | early malloc nằm ngay phía trên `gd_t` |
| `CONFIG_SPL_CUSTOM_SYS_MALLOC_ADDR` | `0x8050_0000` | heap SPL trong DDR |
| `CONFIG_SPL_SYS_MALLOC_SIZE` | `0x0080_0000` | heap SPL đến `0x80D0_0000` |

SPL image thực tế dài `0xD083`, nhỏ hơn giới hạn `0x40000`; `.bss` thực tế
chỉ `0xA8`, nhỏ hơn giới hạn `0x10000`.

### Global data của SPL

Build này có `sizeof(gd_t) = GD_SIZE = 0x100` byte. Trình tự startup RISC-V
tính địa chỉ như sau:

```text
stack_top       = CONFIG_SPL_STACK
                = 0x0806_0000

reserve_stack   = 1 << CONFIG_STACK_SIZE_SHIFT
                = 1 << 14 = 0x4000

reserve_top     = stack_top - reserve_stack
                = 0x0805_C000

gd_base         = rounddown(reserve_top
                            - CONFIG_SPL_SYS_MALLOC_F_LEN
                            - sizeof(gd_t), 16)
                = rounddown(0x0805_C000 - 0x10000 - 0x100, 16)
                = 0x0804_BF00
```

Do đó:

```text
gp/x3, gd       = 0x0804_BF00
gd_t            = [0x0804_BF00, 0x0804_C000)
early malloc    = [0x0804_C000, 0x0805_C000)
SPL stack       = [0x0805_C000, 0x0806_0000), tăng xuống
```

`CONFIG_SPL_STACK_R` không được bật; hàm `spl_relocate_stack_gd()` trong
binary hiện tại chỉ trả về `0`. Vì vậy `gd` vẫn ở `0x0804_BF00` trong toàn
bộ thời gian SPL chạy, cho đến khi chuyển quyền sang OpenSBI.

**Cảnh báo biên:** vùng BSS cấu hình cho phép đến `0x0805_0000`, trong khi
`gd_t` bắt đầu ở `0x0804_BF00`. Hai vùng giới hạn cấu hình chồng nhau trên
`[0x0804_BF00, 0x0805_0000)`, tức `0x4100` byte. `.bss` thực tế hiện chỉ đến
`0x0804_00A8`, nên chưa có overlap runtime. Tuy nhiên chỉ kiểm tra
`CONFIG_SPL_BSS_MAX_SIZE=0x10000` là chưa đủ; để an toàn tuyệt đối, BSS của
SPL phải kết thúc không quá `0x0804_BF00` với layout stack/malloc hiện tại.

## 3. OpenSBI

Nguồn: `buildroot/output/build/opensbi-custom/build/platform/generic/firmware/fw_dynamic.elf`.
`fw_dynamic.elf` là PIE nên địa chỉ section trong ELF là offset. `u-boot.itb`
mới nạp nó tại base **`0x8000_0000`**; bảng sau đã cộng base này.

| Vùng | Start | End | Size |
|---|---:|---:|---:|
| `.text` | `0x8000_0000` | `0x8002_0CF8` | `0x20CF8` (131.24 KiB) |
| gap căn `0x1000` | `0x8002_0CF8` | `0x8002_1000` | `0x308` |
| `.rodata` | `0x8002_1000` | `0x8002_49A8` | `0x39A8` (14.41 KiB) |
| dynamic/relocation metadata | `0x8002_49A8` | `0x8002_7FE8` | `0x3640` (13.56 KiB) |
| gap/căn miền RW | `0x8002_7FE8` | `0x8004_0000` | `0x18018` |
| `.data` | `0x8004_0000` | `0x8004_2970` | `0x2970` (10.36 KiB) |
| `.dynamic`, `.got`, `.htif` | `0x8004_2970` | `0x8004_2AA8` | `0x138` |
| gap căn trang | `0x8004_2AA8` | `0x8004_3000` | `0x558` |
| `.bss` | `0x8004_3000` | `0x8004_3DA8` | `0xDA8` (3.41 KiB) |
| gap đến `_fw_end` | `0x8004_3DA8` | `0x8004_4000` | `0x258` |
| stack hart 0 và 1 | `0x8004_4000` | `0x8004_8000` | `0x4000` (2 × 8 KiB) |
| heap runtime | `0x8004_8000` | `0x8005_2400` | `0xA400` (41 KiB) |

`fw_dynamic.bin` dài `0x42AA8` byte. ELF dành vùng đến `_fw_end =
0x8004_4000`; sau đó OpenSBI tự đặt stack và heap dựa trên hai CPU/hart trong
DTB. Vì vậy vùng OpenSBI cần giữ khi Linux chạy là **`[0x8000_0000,
0x8005_2400)`**, không chỉ kích thước file `.bin`.

## 4. U-Boot proper và DTB được SPL chuyển giao

Nguồn: `buildroot/output/build/uboot-custom/u-boot`, `u-boot.map` và
`u-boot.itb`. Entry/load address mới: **`0x8020_0000`**.

| Vùng | Start | End | Size |
|---|---:|---:|---:|
| `.text` | `0x8020_0000` | `0x8020_0198` | `0x198` |
| `.efi_runtime` | `0x8020_0198` | `0x8020_1118` | `0xF80` |
| `.text_rest` | `0x8020_1140` | `0x8024_9350` | `0x48210` (288.52 KiB) |
| `.rodata` | `0x8024_9350` | `0x8025_AF68` | `0x11C18` (71.02 KiB) |
| dynamic string/hash metadata | `0x8025_AF68` | `0x8025_CD20` | `0x1DB8` |
| `.data` | `0x8025_CD20` | `0x8026_2128` | `0x5408` (21.01 KiB) |
| `.dynamic` | `0x8026_2128` | `0x8026_2238` | `0x110` |
| `.got` | `0x8026_2238` | `0x8026_2980` | `0x748` |
| `__u_boot_list` | `0x8026_2980` | `0x8026_4E58` | `0x24D8` |
| relocation/dynamic symbols | `0x8026_4E58` | `0x8027_2B08` | `0xDCB0` |
| `.bss` | `0x8027_2B08` | `0x8027_C1B0` | `0x96A8` (37.66 KiB) |

Subimage `uboot` trong `u-boot.itb` là `u-boot-nodtb.bin`, dài đúng
`0x72B08` byte và kết thúc tại `0x8027_2B08`. DTB `fdt-1` không có thuộc
tính `load`, nên SPL đặt nó ngay sau U-Boot, căn 8 byte:

```text
U-Boot DTB tạm: [0x8027_2B08, 0x8027_5509), size 0x2A01 (10,753 B)
OpenSBI Next Arg1 / a1 = 0x8027_2B08
```

Vùng DTB tạm trùng với đầu địa chỉ link-time của `.bss`. Đây là cách U-Boot
nhận control FDT ở `_end`; U-Boot phải sử dụng/di chuyển FDT trong quá trình
khởi tạo trước khi vùng nhớ đó được tái sử dụng. Bảng trên mô tả địa chỉ
load/link ban đầu; U-Boot còn có thể tự relocation lên vùng RAM cao hơn.

Trước relocation, startup U-Boot proper dùng
`CONFIG_CUSTOM_SYS_INIT_SP_ADDR=0x8050_0000`. Với stack reserve `0x4000`,
early malloc `CONFIG_SYS_MALLOC_F_LEN=0x10000`, `sizeof(gd_t)=0x148` và phần
cấp phát GD đã căn 16 byte là `0x150`, layout là:

| Vùng hỗ trợ U-Boot trước relocation | Start | End | Size |
|---|---:|---:|---:|
| initial `gd_t` thực dùng | `0x804E_BEB0` | `0x804E_BFF8` | `0x148` |
| padding căn 16 byte sau `gd_t` | `0x804E_BFF8` | `0x804E_C000` | `0x8` |
| early malloc (`CONFIG_SYS_MALLOC_F_LEN`) | `0x804E_C000` | `0x804F_C000` | `0x10000` |
| initial stack reserve | `0x804F_C000` | `0x8050_0000` | `0x4000` |

Địa chỉ `0x8050_0000` đồng thời là đầu heap SPL 8 MiB, nhưng hai cách dùng
thuộc hai giai đoạn kế tiếp nhau: SPL dùng heap trước khi handoff; U-Boot
proper dùng nó làm đỉnh initial stack sau khi SPL đã kết thúc.

### U-Boot proper sau relocation

Địa chỉ trong phần này được tính cho đúng DTB của build hiện tại. Node RAM
chính là `[0x8000_0000, 0xC000_0000)`, nên `gd->ram_top = 0xC000_0000`.
U-Boot tính kích thước monitor gồm cả BSS:

```text
gd->mon_len = __bss_end - __image_copy_start
            = 0x8027_C1B0 - 0x8020_0000
            = 0x7C1B0

gd->relocaddr = ALIGN_DOWN(gd->ram_top - gd->mon_len, 0x1000)
              = ALIGN_DOWN(0xC000_0000 - 0x7C1B0, 0x1000)
              = 0xBFF8_3000
```

Sau đó `board_f.c` dành các vùng từ địa chỉ cao xuống thấp:

```text
0xC000_0000  +----------------------------------+  RAM top
             | U-Boot relocation reserve       |
0xBFF8_3000  +----------------------------------+  gd->relocaddr
             | main malloc, 0x81F000            |
0xBF76_4000  +----------------------------------+
             | bd_info, 0x60                    |
0xBF76_3FA0  +----------------------------------+
             | padding + relocated gd_t, 0x148  |
0xBF76_3E50  +----------------------------------+
             | relocated control FDT, 0x2A20    |
0xBF76_1430  +----------------------------------+
             | stack alignment reserve, 0x10    |
0xBF76_1420  +----------------------------------+  stack top mới
             | stack tăng xuống địa chỉ thấp    |
```

| Vùng sau relocation | Start | End | Size |
|---|---:|---:|---:|
| U-Boot relocated, phần thực dùng đến `__bss_end` | `0xBFF8_3000` | `0xBFFF_F1B0` | `0x7C1B0` |
| U-Boot relocation reserve, gồm padding căn trang | `0xBFF8_3000` | `0xC000_0000` | `0x7D000` |
| main malloc arena | `0xBF76_4000` | `0xBFF8_3000` | `0x81F000` |
| relocated `bd_info` | `0xBF76_3FA0` | `0xBF76_4000` | `0x60` |
| relocated `gd_t` thực dùng | `0xBF76_3E50` | `0xBF76_3F98` | `0x148` (328 B) |
| padding sau `gd_t` | `0xBF76_3F98` | `0xBF76_3FA0` | `0x8` |
| relocated control FDT | `0xBF76_1430` | `0xBF76_3E50` | `0x2A20` đã căn 32 B |
| stack alignment reserve | `0xBF76_1420` | `0xBF76_1430` | `0x10` |

Main malloc có tổng kích thước `0x81F000`, không chỉ `0x800000`:

```text
TOTAL_MALLOC_LEN = CONFIG_SYS_MALLOC_LEN + CONFIG_ENV_SIZE
                 = 0x800000 + 0x1F000
                 = 0x81F000
```

Stack mới có đỉnh **`0xBF76_1420`** và tăng xuống địa chỉ thấp. Sau
relocation, RISC-V `arch_reserve_stacks()` không dành thêm một vùng stack có
kích thước cố định; `0x10` trong bảng chỉ là bước căn chỉnh con trỏ stack.
Do đó không nên diễn giải stack sau relocation là một vùng 16 KiB như stack
ban đầu.

Các địa chỉ sau relocation phụ thuộc `gd->ram_top`, kích thước U-Boot, FDT
và cấu hình malloc. Nếu DTB/runtime báo dung lượng RAM khác build hiện tại,
phải tính lại từ công thức trên; ví dụ log cũ báo `DRAM: 2 GiB` sẽ cho một
layout relocation khác.

#### Vì sao địa chỉ `0xBFxx_xxxx` hợp lệ?

`0xB000_0000` không phải là một bank RAM riêng. Nó nằm bên trong bank DDR
chính được DTB hiện tại khai báo:

```dts
memory@80000000 {
    device_type = "memory";
    reg = <0x80000000 0x40000000>;
};
```

Địa chỉ cuối được tính bằng base cộng size:

```text
DDR start = 0x8000_0000
DDR size  = 0x4000_0000 = 1 GiB
DDR end   = 0xC000_0000

Vùng hợp lệ: [0x8000_0000, 0xC000_0000)
```

Chia bank DDR này thành các đoạn 256 MiB sẽ thấy toàn bộ vùng `0xB...` nằm
trong DDR:

| Khoảng địa chỉ | Kích thước | Thuộc DDR chính |
|---|---:|---|
| `0x8000_0000` – `0x8FFF_FFFF` | 256 MiB | có |
| `0x9000_0000` – `0x9FFF_FFFF` | 256 MiB | có |
| `0xA000_0000` – `0xAFFF_FFFF` | 256 MiB | có |
| `0xB000_0000` – `0xBFFF_FFFF` | 256 MiB | có |

Do đó `0xBF76_1420`, `0xBF76_4000` và `0xBFF8_3000` đều nhỏ hơn
`0xC000_0000` và nằm trong bank `memory@80000000`. Device Tree không cần
thêm node `memory@b0000000`.

Nếu phần cứng thực tế chỉ ánh xạ 512 MiB tại
`[0x8000_0000, 0xA000_0000)`, thì khai báo DTB `size = 0x4000_0000` là sai
và layout relocation `0xBF...` không an toàn. Có thể kiểm tra giá trị U-Boot
thực sự đang dùng bằng console:

```console
=> bdinfo
=> md.l 0xbff83000 4
=> mw.l 0xb0000000 0x12345678
=> md.l 0xb0000000 1
```

`bdinfo` là phép kiểm tra an toàn hơn vì chỉ đọc trạng thái. Hai lệnh `mw.l`
và `md.l` cuối dùng để thử RAM nhưng sẽ ghi đè nội dung tại địa chỉ kiểm tra;
chỉ thực hiện trên một vùng scratch đã chắc chắn không chứa code, dữ liệu,
DTB, heap hoặc stack.

## 5. Linux kernel

`fitImage.itb` được `fatload` vào **`0x9000_0000`** (giá trị `loadaddr`) và
chiếm `[0x9000_0000, 0x90C7_1628)`. Kernel bên trong là `Image.gz`, dài
`0x30E9A9`, có `load = entry = 0x8280_0000`. U-Boot giải nén thành `Image`
dài `0xCB1A00` tại `0x8280_0000`.

`vmlinux` link ở virtual `0xFFFF_FFFF_8000_0000`. Địa chỉ physical dưới đây
được tính theo:

```text
physical = 0x8280_0000 + (virtual - 0xFFFF_FFFF_8000_0000)
```

| Vùng Linux | Physical start | Physical end | Size |
|---|---:|---:|---:|
| `.head.text` | `0x8280_0000` | `0x8280_1EA6` | `0x1EA6` |
| `.text` | `0x8280_2000` | `0x82BD_33B2` | `0x3D13B2` (3,908.92 KiB) |
| `.init.text` | `0x82C0_0000` | `0x82C2_FEE0` | `0x2FEE0` |
| `.exit.text` | `0x82C2_FEE0` | `0x82C3_0842` | `0x962` |
| `.init.data` | `0x82E0_0000` | `0x82E0_DC60` | `0xDC60` |
| `.init.pi` | `0x82E0_DC60` | `0x82E1_070A` | `0x2AAA` |
| `.init.bss` | `0x82E1_0710` | `0x82E1_0758` | `0x48` |
| runtime fields | `0x82E1_0758` | `0x82E1_07AC` | `0x54` |
| `.alternative` | `0x82E1_1000` | `0x82E1_8F70` | `0x7F70` |
| `.rodata` | `0x8300_0000` | `0x830E_D0A0` | `0xED0A0` (948.16 KiB) |
| `__param`, `__modver`, `__ex_table`, notes | `0x830E_D0A0` | `0x830E_F220` | `0x2180` |
| `.srodata` | `0x8320_0000` | `0x8320_0338` | `0x338` |
| `.data` | `0x8340_0000` | `0x834A_5720` | `0xA5720` (661.78 KiB) |
| `__bug_table` | `0x834A_5720` | `0x834B_0FC4` | `0xB8A4` |
| `.sdata` | `0x834B_0FC8` | `0x834B_19D8` | `0xA10` |
| PE/COFF padding; cuối file `Image` | `0x834B_19D8` | `0x834B_1A00` | `0x28` |
| `.sbss` | `0x834B_2000` | `0x834B_32CD` | `0x12CD` |
| `.bss` | `0x834B_4000` | `0x834F_5CD0` | `0x41CD0` (263.20 KiB) |
| căn trang đến `_end` | `0x834F_5CD0` | `0x834F_6000` | `0x330` |

Như vậy Linux cần vùng physical tối thiểu **`[0x8280_0000,
0x834F_6000)`** cho image tĩnh và BSS của build này. Các vùng cấp phát động
sau khi kernel chạy không nằm trong bảng.

## 6. NPU firmware

Địa chỉ chạy NPU không lấy từ `CONFIG_CVA6_SPL_NPU_FIT_ADDR`. SPL đọc
`load` và `entry` trong `NPU_fw.itb`, giống như cách nó đọc địa chỉ OpenSBI
và U-Boot từ `u-boot.itb`.

Nguồn và artifact NPU đã thống nhất tại **`0x8400_0000`**:

- `configs/genesys2/npu_fw_dummy/npu_fw.ld` đặt `ORIGIN = 0x8400_0000`,
  `LENGTH = 1M`.
- `configs/genesys2/npu_fw_dummy/viettel_npu.its` đặt
  `load = entry = 0x8400_0000`.
- `configs/genesys2/npu_fw_dummy/build/npu_fw/npu_fw.elf` có entry
  `0x8400_0000` và `.text` dài 4 byte.

| Vùng NPU hiện tại | Start | End | Size |
|---|---:|---:|---:|
| `.text` / raw payload | `0x8400_0000` | `0x8400_0004` | `0x4` |
| căn đến `__image_end` | `0x8400_0004` | `0x8400_0010` | `0xC` |
| vùng DDR dành theo linker script | `0x8400_0000` | `0x8410_0000` | `0x0010_0000` (1 MiB) |

### Artifact NPU đã xác nhận

`configs/genesys2/npu_fw_dummy/NPU_fw.itb` được tạo lại lúc
2026-08-27 11:32:21, size `0x2BA`. Metadata FIT, ELF và map đều khớp:

| Thành phần | Kết quả kiểm tra |
|---|---|
| `npu_fw.bin` | size `0x4` |
| `npu_fw.elf` | entry `0x8400_0000`, `.text = [0x8400_0000, 0x8400_0004)` |
| `npu_fw.map` | `__image_start = 0x8400_0000`, `__image_end = 0x8400_0010` |
| `NPU_fw.itb` | `load = entry = 0x8400_0000`, payload size `0x4`, FIT size `0x2BA` |

Có thể xác nhận lại artifact bằng:

```sh
make -C configs/genesys2/npu_fw_dummy fit
buildroot/output/host/bin/dumpimage -l \
  configs/genesys2/npu_fw_dummy/NPU_fw.itb
buildroot/output/host/bin/fdtget -tx \
  configs/genesys2/npu_fw_dummy/NPU_fw.itb /images/npu-fw load
buildroot/output/host/bin/fdtget -tx \
  configs/genesys2/npu_fw_dummy/NPU_fw.itb /images/npu-fw entry
```

`CONFIG_CVA6_SPL_NPU_FIT_ADDR=0x0050_0000` là địa chỉ **FIT container đã
được pre-load** cho đường loader DDR, không phải địa chỉ NPU chạy. Đường QSPI
dùng `CONFIG_CVA6_SPL_QSPI_NPU_FIT_OFFSET`; payload cuối cùng vẫn đi đến
`load` trong NPU FIT. Vì DDR được khai báo bắt đầu tại `0x8000_0000`, giá trị
`0x0050_0000` hiện không thuộc bank DDR này; nó chỉ trùng về số với QSPI
offset. Nếu cần giữ đường loader DDR làm fallback thì phải đặt lại địa chỉ
source FIT hợp lệ. Tương tự, `CONFIG_SPL_LOAD_FIT_ADDRESS=0` hiện không phải
một staging address DDR hợp lệ cho `u-boot.itb`.

## 7. Bố trí địa chỉ QSPI

Đây là **offset byte trong flash**, không phải địa chỉ DDR mà CPU jump đến.
Driver SPL hiện giới hạn media QSPI là `0x0080_0000` byte, tức 8 MiB và miền
offset hợp lệ là `[0x0000_0000, 0x0080_0000)`.

| Nội dung QSPI | Start offset | End offset | Size/ghi chú |
|---|---:|---:|---|
| Dữ liệu boot trước các FIT | `0x0000_0000` | `0x0030_0000` | U-Boot loader không mô tả chi tiết; Kconfig nhắc đến các BootROM slot |
| vùng loader chấp nhận cho `u-boot.itb` | `0x0030_0000` | `0x0050_0000` | giới hạn hiệu lực 2 MiB |
| `u-boot.itb` build hiện tại | `0x0030_0000` | `0x003B_8799` | size `0xB8799` |
| phần trống sau `u-boot.itb` hiện tại | `0x003B_8799` | `0x0050_0000` | `0x147867` |
| vùng loader chấp nhận cho `NPU_fw.itb` | `0x0050_0000` | `0x0070_0000` | giới hạn hiệu lực 2 MiB |
| `NPU_fw.itb` hiện tại | `0x0050_0000` | `0x0050_02BA` | size `0x2BA`; payload load vào DDR `0x8400_0000` |
| phần trống trong vùng NPU hiện tại | `0x0050_02BA` | `0x0070_0000` | `0x1FFD46` |
| phần QSPI ngoài hai vùng FIT | `0x0070_0000` | `0x0080_0000` | `0x100000` |

Luồng đọc QSPI là:

```text
QSPI 0x0030_0000: u-boot.itb
    ├─ OpenSBI payload -> DDR 0x8000_0000
    ├─ U-Boot payload  -> DDR 0x8020_0000
    └─ control DTB     -> DDR 0x8027_2B08

QSPI 0x0050_0000: NPU_fw.itb
    └─ NPU payload     -> DDR 0x8400_0000
```

SPL chỉ đọc các đoạn FIT cần thiết qua callback SPI; toàn bộ ITB không được
copy đến một địa chỉ staging DDR.

### Giới hạn FIT được QSPI loader sử dụng

`cva6_load_images_from_spi()` lấy hai offset QSPI nhưng truyền các giới hạn
FIT dùng chung vào `cva6_spl_spi_load_fit()`. Giá trị hiệu lực của build mới
là:

```text
CONFIG_CVA6_SPL_QSPI_UBOOT_FIT_OFFSET = 0x00300000
CONFIG_CVA6_SPL_UBOOT_FIT_MAX_SIZE    = 0x00200000
CONFIG_CVA6_SPL_QSPI_NPU_FIT_OFFSET   = 0x00500000
CONFIG_CVA6_SPL_NPU_FIT_MAX_SIZE      = 0x00200000
```

Điều kiện biên của `cva6_spl_spi_load_fit()` hiện thỏa mãn:

```text
U-Boot: 0x00300000 + 0x00200000 = 0x00500000 <= 0x00800000
NPU:    0x00500000 + 0x00200000 = 0x00700000 <= 0x00800000
```

`u-boot.itb` size `0xB8799` và `NPU_fw.itb` size `0x2BA` đều nhỏ hơn giới
hạn `0x00200000`. Vì vậy lỗi kiểm tra size/biên QSPI trước đây đã được sửa.
Hai biến `CONFIG_CVA6_SPL_QSPI_*_FIT_MAX_SIZE` vẫn tồn tại trong `.config`,
nhưng code loader hiện tại không truyền chúng vào hàm đọc; cận hiệu lực là
hai giá trị `CONFIG_CVA6_SPL_*_FIT_MAX_SIZE` ở trên.

## 8. DTS/DTB và initramfs

DTS là mã nguồn mô tả phần cứng; sau khi biên dịch, DTB là một blob dữ liệu.
Nó không có các section `.text`, `.data`, `.bss` như ELF.

| Blob | Size | Địa chỉ xác định từ build |
|---|---:|---|
| SPL control DTB | `0x943` | nối cuối SPL tại `0x0800_C740` |
| U-Boot/Linux DTB | `0x2A01` | SPL đặt tạm tại `0x8027_2B08` |
| DTB trong `fitImage.itb` | `0x2A01` | không có `load`; U-Boot/LMB chọn địa chỉ cuối lúc `bootm` |
| initramfs nén | `0x95FD78` | không có `load`; U-Boot/LMB chọn địa chỉ cuối lúc `bootm` |

Vì `fitImage.its` không khai báo `load` cho `fdt-1` và `ramdisk-1`, không thể
suy ra một địa chỉ runtime cố định chỉ từ file build. Muốn ghi lại địa chỉ
chính xác của một lần boot, lấy các dòng `Loading Device Tree to ...` và
`Loading Ramdisk to ...` từ console U-Boot; các địa chỉ có thể thay đổi khi
kích thước image, RAM hoặc biến `fdt_high`/`initrd_high` thay đổi.

## 9. Kiểm tra overlap

- SPL trong OCM không chồng OpenSBI/U-Boot/Linux trong DDR.
- OpenSBI runtime kết thúc tại `0x8005_2400`, trước U-Boot ở `0x8020_0000`.
- U-Boot kết thúc tại `0x8027_C1B0`, trước initial GD/malloc/stack của U-Boot
  proper quanh `0x804E_BEB0` và heap SPL ở `0x8050_0000`.
- Linux không chồng vùng link/load ban đầu của OpenSBI hoặc U-Boot. Kernel có
  thể tái sử dụng vùng U-Boot về sau, sau khi U-Boot đã chuyển quyền.
- Linux static/BSS kết thúc tại `0x834F_6000`, trước vùng NPU hiện tại
  `[0x8400_0000, 0x8410_0000)`.
- DTB hiện không có node `reserved-memory` cho `[0x8400_0000, 0x8410_0000)`.
  Dù không chồng image tĩnh, Linux page allocator vẫn có thể cấp phát vùng
  này. Phải reserve 1 MiB này trong DTS (thường dùng `no-map`) trước khi cho
  NPU chạy đồng thời với Linux.
- QSPI là media/không gian offset riêng, nên các offset `0x0030_0000` và
  `0x0050_0000` không chồng các địa chỉ DDR có cùng giá trị số.

## 10. Lệnh đối chiếu nhanh

```sh
readelf -W -S buildroot/output/build/uboot-custom/spl/u-boot-spl
readelf -W -S buildroot/output/build/uboot-custom/u-boot
readelf -W -S buildroot/output/build/opensbi-custom/build/platform/generic/firmware/fw_dynamic.elf
readelf -W -S buildroot/output/build/linux-6.19.6/vmlinux
dumpimage -l buildroot/output/build/uboot-custom/u-boot.itb
dumpimage -l install64_genesys2/fitImage.itb
dumpimage -l configs/genesys2/npu_fw_dummy/NPU_fw.itb
fdtget -tx configs/genesys2/npu_fw_dummy/NPU_fw.itb \
  /images/npu-fw load
fdtget -tx configs/genesys2/npu_fw_dummy/NPU_fw.itb \
  /images/npu-fw entry
```

## 11. Cách xác định địa chỉ và nguồn số liệu

### 11.1. Chọn đúng bộ build

Các binary trong `install64_genesys2` được so SHA-256 với artifact trong
`buildroot/output/build`. SPL, U-Boot, OpenSBI và Linux đều khớp từng cặp.
Việc này tránh lấy nhầm snapshot cũ trong `1040_307_01_jumped_2_opensbi`.

```sh
sha256sum install64_genesys2/u-boot-spl.bin \
  buildroot/output/build/uboot-custom/spl/u-boot-spl.bin
sha256sum install64_genesys2/u-boot.bin \
  buildroot/output/build/uboot-custom/u-boot.bin
```

### 11.2. Nguồn của từng loại địa chỉ

| Thông tin | Nguồn chính | Cách đọc |
|---|---|---|
| Entry point, `.text`, `.rodata`, `.data`, `.bss` | ELF tương ứng | `readelf -W -h`, `readelf -W -S`, `readelf -W -l` |
| Symbol `_end`, `__bss_start`, `__bss_end` | file `.map`, `System.map` hoặc symbol table ELF | `rg` trong `.map`; `nm -n`; `readelf -W -s` |
| Địa chỉ/giới hạn SPL và U-Boot | `buildroot/output/build/uboot-custom/.config` | các biến `CONFIG_SPL_*`, `CONFIG_TEXT_BASE`, `CONFIG_SYS_*` |
| Cách linker bố trí SPL BSS | `arch/riscv/cpu/u-boot-spl.lds` | vùng `MEMORY .bss_mem` và section `.bss` |
| Cách RISC-V dành stack trước khi tạo GD | `arch/riscv/cpu/start.S` | `CONFIG_VAL(STACK)`, `CONFIG_STACK_SIZE_SHIFT`, lời gọi `board_init_f_alloc_reserve` |
| Công thức đặt GD và early malloc | `common/init/board_init.c` | `board_init_f_alloc_reserve()` và `board_init_f_init_reserve()` |
| Kích thước SPL `gd_t` | `spl/include/generated/generic-asm-offsets.h` | `GD_SIZE=256`, `GENERATED_GBL_DATA_SIZE=256` |
| Thanh ghi giữ con trỏ GD trên RISC-V | `arch/riscv/include/asm/global_data.h` | `DECLARE_GLOBAL_DATA_PTR ... asm("gp")` |
| Địa chỉ load OpenSBI/U-Boot/Linux | FIT image | `dumpimage -l u-boot.itb` và `dumpimage -l fitImage.itb` |
| Địa chỉ load/entry NPU | `NPU_fw.itb` | `dumpimage -l`; đọc riêng hai property `load` và `entry` bằng `fdtget -tx` |
| Vùng link NPU | `npu_fw.elf`, `npu_fw.map`, `npu_fw.ld` | `readelf -W -h -S`, map và `MEMORY` trong linker script |
| Offset FIT trong QSPI | U-Boot `.config` và board loader | `CONFIG_CVA6_SPL_QSPI_*_OFFSET`; đối chiếu đối số gọi `cva6_spl_spi_load_fit()` |
| Dung lượng/cận QSPI | `board/openhwgroup/cva6_genesysII/spl_spi.c` | `CVA6_SPI_FLASH_SIZE` và kiểm tra `offset + max_size` |
| Layout U-Boot proper sau relocation | `common/board_f.c`, `common/board_r.c`, `include/env_internal.h`, DTB và `.config` | `setup_dest_addr()`, `reserve_uboot()`, `reserve_malloc()`, `reserve_fdt()`, `reserve_stacks()` |
| Section OpenSBI PIE | `fw_dynamic.elf` | lấy offset section rồi cộng load base `0x8000_0000` |
| Stack/heap runtime OpenSBI | `firmware/fw_base.S`, `platform/generic/platform.c`, DTB | `_fw_end` + số hart × stack size + heap tính theo số hart |
| DTB đặt sau U-Boot | `common/spl/spl_fit.c` | `spl_fit_append_fdt()` dùng `ALIGN(load_addr + size, 8)` |
| Địa chỉ physical section Linux | `vmlinux`, `System.map`, FIT | cộng offset virtual từ link base vào physical load base `0x8280_0000` |
| DTB/initramfs Linux runtime | FIT và log U-Boot | không có `load`; lấy dòng `Loading Device Tree/Loading Ramdisk` khi boot |

Các đường dẫn nguồn U-Boot trong bảng trên đều tính tương đối từ
`buildroot/output/build/uboot-custom`. Nguồn OpenSBI tính từ
`buildroot/output/build/opensbi-custom`; nguồn Linux tính từ
`buildroot/output/build/linux-6.19.6`.

### 11.3. Kiểm tra riêng địa chỉ global data SPL

Ngoài việc tính từ mã nguồn, có thể xác nhận trực tiếp từ binary:

```sh
# Kích thước gd_t của đúng cấu hình SPL
rg 'GD_SIZE|GENERATED_GBL_DATA_SIZE' \
  buildroot/output/build/uboot-custom/spl/include/generated/generic-asm-offsets.h

# Xem startup nạp stack 0x08060000, trừ stack 0x4000 và gọi hàm reserve
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-objdump -d \
  --start-address=0x08000000 --stop-address=0x08000070 \
  buildroot/output/build/uboot-custom/spl/u-boot-spl

# Xem hàm reserve trừ tổng 0x10100 = malloc 0x10000 + gd 0x100
buildroot/output/host/bin/riscv64-buildroot-linux-gnu-objdump -d \
  --start-address=0x080021c0 --stop-address=0x080021f4 \
  buildroot/output/build/uboot-custom/spl/u-boot-spl
```

Disassembly hiện tại cho thấy `board_init_f_alloc_reserve()` trừ đúng
`0x10100`; từ input `0x0805_C000`, kết quả là **`0x0804_BF00`**. Sau khi
`board_init_f_init_reserve()` chạy, lệnh `mv gp, s0` đặt con trỏ GD RISC-V
vào địa chỉ này.
