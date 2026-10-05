---
title: "Các config ẩn của U-Boot – Genesys2 + Viettel"
lang: vi-VN
---

# Các config ẩn của U-Boot – Genesys2 + Viettel

**Nguồn đối chiếu:**

- `configs/genesys2/uboot64_defconfig`
- `buildroot/output/build/uboot-custom/.config`
- `buildroot/output/build/uboot-custom/board/openhwgroup/cva6_genesysII/Kconfig`

**Tiêu chí:** Config có hiệu lực trong `.config` sau build nhưng bị ẩn khỏi giao diện `menuconfig` do không có prompt, dependency không hiển thị, hoặc được tự động bật bằng `select`, `imply` hay giá trị mặc định.

**Quy ước:** `y` = bật; “không có” = không có đơn vị vật lý.

## Nhận dạng board Genesys2

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_SYS_ARCH` | `riscv` (chuỗi) | Tên kiến trúc của target, tự động sinh khi chọn RISC-V. |
| `CONFIG_SYS_CPU` | `generic` (chuỗi) | CPU generic được đặt mặc định bởi Kconfig của Genesys2. |
| `CONFIG_SYS_VENDOR` | `openhwgroup` (chuỗi) | Tên vendor của board. |
| `CONFIG_SYS_BOARD` | `cva6_genesysII` (chuỗi) | Tên board dùng khi chọn target CVA6 Genesys II. |
| `CONFIG_SYS_CONFIG_NAME` | `openhwgroup_cva6_genesysII` (chuỗi) | Chọn header cấu hình của board Genesys2. |
| `CONFIG_BOARD_SPECIFIC_OPTIONS` | `y` (không có) | Config dummy ẩn, tự bật khi target Genesys2 được chọn và kéo theo các dependency của board. |

## Config được board Genesys2 tự động chọn

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_GENERIC_RISCV` | `y` (không có) | Được `CONFIG_BOARD_SPECIFIC_OPTIONS` chọn; bật nền tảng RISC-V generic. |
| `CONFIG_SUPPORT_SPL` | `y` (không có) | Được board chọn để khai báo nền tảng có hỗ trợ SPL. |
| `CONFIG_SPL_RAM` | `y` (không có) | Được board chọn khi `CONFIG_SPL=y`; đưa RAM subsystem vào SPL. |
| `CONFIG_ARCH_EARLY_INIT_R` | `y` (không có) | Được `CONFIG_GENERIC_RISCV` chọn; bật hàm khởi tạo kiến trúc ở giai đoạn `init_r`. |
| `CONFIG_BINMAN` | `y` (không có) | Được `CONFIG_GENERIC_RISCV` chọn khi có SPL; hỗ trợ đóng gói các image boot. |

## Config tự động sinh từ kiến trúc RISC-V

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_CREATE_ARCH_SYMLINK` | `y` (không có) | Tạo liên kết kiến trúc cần thiết trong quá trình build RISC-V. |
| `CONFIG_HAVE_SETJMP` | `y` (không có) | Cho biết kiến trúc hỗ trợ `setjmp()` và `longjmp()`. |
| `CONFIG_HAVE_INITJMP` | `y` (không có) | Bật hàm `initjmp()` đi kèm cơ chế `setjmp()`. |
| `CONFIG_SUPPORT_LITTLE_ENDIAN` | `y` (không có) | Cho biết target hỗ trợ thứ tự byte little-endian. |
| `CONFIG_SUPPORT_ACPI` | `y` (không có) | Hạ tầng ACPI được kiến trúc RISC-V chọn tự động. |
| `CONFIG_SUPPORT_OF_CONTROL` | `y` (không có) | Cho biết kiến trúc hỗ trợ điều khiển phần cứng qua Device Tree. |
| `CONFIG_DM` | `y` (không có) | Bật Driver Model cốt lõi, được kiến trúc RISC-V chọn. |
| `CONFIG_DM_EVENT` | `y` (không có) | Bật hệ thống sự kiện của Driver Model. |
| `CONFIG_BLK` | `y` (không có) | Bật block-device layer; được RISC-V và các driver lưu trữ kéo theo. |
| `CONFIG_DM_MMC` | `y` (không có) | MMC/eMMC sử dụng Driver Model. |

## Config tự động sinh từ RV64 và SPL

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_64BIT` | `y` (không có) | Được `CONFIG_ARCH_RV64I` chọn; U-Boot proper được build 64-bit. |
| `CONFIG_SPL_64BIT` | `y` (không có) | Được `CONFIG_ARCH_RV64I` chọn khi SPL được bật; SPL được build 64-bit. |
| `CONFIG_DMA_ADDR_T_64BIT` | `y` (không có) | Kiểu địa chỉ DMA có độ rộng 64-bit. |
| `CONFIG_SYS_CACHE_SHIFT_6` | `y` (không có) | Được nền tảng RISC-V generic chọn; cache-line shift bằng 6. |
| `CONFIG_SYS_CACHELINE_SIZE` | `64` byte | Kích thước cache line, suy ra từ `2^CONFIG_SYS_CACHE_SHIFT_6`. |
| `CONFIG_SPL_RISCV_ACLINT` | `y` (không có) | Bật ACLINT trong SPL khi SPL chạy ở RISC-V Machine Mode. |
| `CONFIG_SBI` | `y` (không có) | Bật giao tiếp Supervisor Binary Interface cho RISC-V. |

## Giá trị bộ nhớ được tự động suy ra

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_HAVE_TEXT_BASE` | `y` (không có) | Cho biết target có địa chỉ `TEXT_BASE` hợp lệ. |
| `CONFIG_SYS_UBOOT_START` | `0x80400000` (địa chỉ byte) | Địa chỉ bắt đầu U-Boot, tự động suy ra từ `CONFIG_TEXT_BASE`. |

## Device Tree Viettel được truyền sang SPL

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_OF_REAL` | `y` (không có) | Cho biết U-Boot proper sử dụng Device Tree thật. |
| `CONFIG_SPL_OF_LIST` | `viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig` (chuỗi) | Device Tree Viettel được tự động truyền từ danh sách DT của U-Boot sang SPL. |
| `CONFIG_SPL_OF_REAL` | `y` (không có) | Cho biết SPL sử dụng Device Tree thật. |

## Config ẩn đã được ghi trực tiếp trong defconfig

| Tên config | Giá trị (đơn vị) | Ý nghĩa / nguồn kích hoạt |
|---|---|---|
| `CONFIG_SPL_RAM_SUPPORT` | `y` (không có) | Config không có prompt trong Kconfig nhưng đã được khai báo trực tiếp trong `uboot64_defconfig`; bật boot SPL từ image có sẵn trong RAM. |

## Lưu ý về menu Viettel

Các config sau thuộc menu **VIETTEL SPL FIT loader**, nhưng không phải config ẩn. Chúng xuất hiện trong `menuconfig` khi `CONFIG_SPL=y` và các dependency tương ứng được thỏa mãn:

- `CONFIG_SPL_NPU_HANDOFF_BUILD`
- `CONFIG_NPU_HANDOFF_BYJUMP_BUILD`
- `CONFIG_CVA6_SPL_UBOOT_FIT_MAX_SIZE`
- `CONFIG_CVA6_SPL_NPU_FIT_ADDR`
- `CONFIG_CVA6_SPL_NPU_FIT_MAX_SIZE`
- `CONFIG_CVA6_SPL_UBOOT_FIT_FILENAME`
- `CONFIG_CVA6_SPL_NPU_FIT_FILENAME`
- `CONFIG_CVA6_SPL_EMMC_DEVICE`

Toàn bộ tám config trên hiện đã được khai báo trực tiếp trong `configs/genesys2/uboot64_defconfig`.
