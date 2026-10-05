---
title: "Bảng cấu hình U-Boot 64-bit – CVA6 Genesys II"
lang: vi-VN
---

# Bảng cấu hình U-Boot 64-bit – CVA6 Genesys II

**Nguồn:** `configs/genesys2/uboot64_defconfig`

**Quy ước:** `y` = bật; `n` = tắt; “Không có” = không có đơn vị vật lý.

## Kiến trúc và bộ nhớ chính

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_RISCV` | `y` (không có) | Xây dựng U-Boot cho kiến trúc RISC-V. |
| `CONFIG_ARCH_RV64I` | `y` (không có) | Sử dụng kiến trúc RISC-V 64-bit RV64I. |
| `CONFIG_RISCV_SMODE` | `y` (không có) | U-Boot chạy ở Supervisor Mode. |
| `CONFIG_TARGET_OPENHWGROUP_CVA6_GENESYSII` | `y` (không có) | Chọn target CVA6 trên bo Genesys II. |
| `CONFIG_NR_DRAM_BANKS` | `1` bank | Khai báo một vùng/bank DRAM. |
| `CONFIG_SYS_MALLOC_LEN` | `0x00800000` = 8 MiB | Dung lượng heap của U-Boot sau relocation. |
| `CONFIG_SYS_MALLOC_F_LEN` | `0x10000` = 64 KiB | Heap tạm dùng trước relocation. |
| `CONFIG_HAS_CUSTOM_SYS_INIT_SP_ADDR` | `y` (không có) | Cho phép chỉ định địa chỉ stack khởi tạo. |
| `CONFIG_CUSTOM_SYS_INIT_SP_ADDR` | `0x80700000` (địa chỉ byte) | Đỉnh stack khởi tạo của U-Boot. |
| `CONFIG_TEXT_BASE` | `0x80400000` (địa chỉ byte) | Địa chỉ cơ sở nơi U-Boot proper được liên kết/chạy. |
| `CONFIG_SYS_LOAD_ADDR` | `0x90000000` (địa chỉ byte) | Địa chỉ RAM mặc định khi nạp kernel hoặc image. |
| `CONFIG_SYS_BOOTM_LEN` | `0x04000000` = 64 MiB | Kích thước vùng tối đa dùng khi `bootm` giải nén hoặc xử lý image. |

## Device Tree và định dạng image

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_DEFAULT_DEVICE_TREE` | `viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig` (chuỗi) | Device Tree mặc định của phần cứng CVA6/Viettel. |
| `CONFIG_OF_UPSTREAM` | `y` (không có) | Lấy Device Tree từ cây DTS upstream. |
| `CONFIG_OF_BOARD_SETUP` | `y` (không có) | Cho phép code của board chỉnh sửa FDT trước khi boot hệ điều hành. |
| `CONFIG_FIT` | `y` (không có) | Bật hỗ trợ FIT image. |
| `CONFIG_LEGACY_IMAGE_FORMAT` | Tắt (không có) | Không hỗ trợ định dạng legacy `uImage`. |
| `CONFIG_RANDOM_UUID` | Tắt (không có) | Không sinh UUID ngẫu nhiên trong U-Boot. |

## Quá trình boot

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_BOOTDELAY` | `5` giây | Chờ 5 giây trước khi chạy lệnh boot tự động. |
| `CONFIG_USE_BOOTCOMMAND` | `y` (không có) | Sử dụng boot command được cấu hình cố định. |
| `CONFIG_BOOTCOMMAND` | `mmc info; fatload mmc 0:2; bootm` (chuỗi lệnh) | Khởi tạo MMC, nạp image từ phân vùng FAT `0:2`, sau đó chạy `bootm`. |
| `CONFIG_USE_BOOTFILE` | `y` (không có) | Bật tên boot file mặc định. |
| `CONFIG_BOOTFILE` | `fitImage.itb` (tên file) | Tên FIT image mặc định cần nạp. |
| `CONFIG_DISPLAY_CPUINFO` | `y` (không có) | Hiển thị thông tin CPU khi U-Boot khởi động. |
| `CONFIG_ENV_OVERWRITE` | `y` (không có) | Cho phép ghi đè các biến môi trường được bảo vệ như serial hoặc MAC. |

## Các lệnh U-Boot

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_CMD_GPT` | `y` (không có) | Bật lệnh thao tác bảng phân vùng GPT. |
| `CONFIG_CMD_MMC` | `y` (không có) | Bật nhóm lệnh MMC/eMMC/SD. |
| `CONFIG_CMD_PART` | `y` (không có) | Bật lệnh xem và thao tác phân vùng. |
| `CONFIG_CMD_DHCP` | `y` (không có) | Cho phép lấy IP và nạp file qua DHCP. |
| `CONFIG_CMD_MDIO` | `y` (không có) | Bật lệnh truy cập bus MDIO của Ethernet PHY. |
| `CONFIG_CMD_PING` | `y` (không có) | Bật lệnh kiểm tra kết nối mạng bằng ping. |
| `CONFIG_CMD_FAT` | `y` (không có) | Bật đọc filesystem FAT. |

## MMC, SPI, Ethernet và UART

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_MMC` | `y` (không có) | Bật hệ thống MMC/eMMC/SD. |
| `CONFIG_MMC_WRITE` | Tắt (không có) | Không cho phép ghi MMC từ U-Boot. |
| `CONFIG_MMC_SPI` | `y` (không có) | Bật giao tiếp thẻ MMC/SD qua SPI. |
| `CONFIG_SPI` | `y` (không có) | Bật SPI framework. |
| `CONFIG_XILINX_SPI` | `y` (không có) | Bật driver SPI controller của Xilinx. |
| `CONFIG_PHY_REALTEK` | `y` (không có) | Bật driver Ethernet PHY Realtek. |
| `CONFIG_SYS_NS16550` | `y` (không có) | Bật driver UART tương thích NS16550. |
| `CONFIG_LOWRISC_DIGILENT_100MHZ` | Comment/tắt (không có) | Cấu hình Ethernet LowRISC/Digilent 100 MHz hiện không được sử dụng. |

## SPL và OpenSBI

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_SPL` | `y` (không có) | Xây dựng SPL, bootloader giai đoạn đầu. |
| `CONFIG_SPL_TEXT_BASE` | `0x80000000` (địa chỉ byte) | Địa chỉ chạy phần mã SPL. |
| `CONFIG_SPL_HAVE_INIT_STACK` | `y` (không có) | SPL có stack khởi tạo riêng. |
| `CONFIG_SPL_STACK` | `0x80200000` (địa chỉ byte) | Đỉnh stack của SPL. |
| `CONFIG_SPL_BSS_START_ADDR` | `0x80040000` (địa chỉ byte) | Địa chỉ bắt đầu vùng BSS của SPL. |
| `CONFIG_SPL_BSS_MAX_SIZE` | `0x10000` = 64 KiB | Kích thước BSS tối đa của SPL. |
| `CONFIG_SPL_MAX_SIZE` | `0x40000` = 256 KiB | Kích thước binary SPL tối đa. |
| `CONFIG_SPL_OPENSBI_LOAD_ADDR` | `0x80200000` (địa chỉ byte) | Địa chỉ SPL nạp OpenSBI. |
| `CONFIG_SPL_LOAD_FIT` | `y` (không có) | Cho phép SPL nạp và phân tích FIT image. |
| `CONFIG_SPL_LOAD_FIT_ADDRESS` | `0x82800000` (địa chỉ byte) | Địa chỉ cố định dùng để nạp FIT image. |
| `CONFIG_SPL_SMP` | `n` (không có) | Tắt xử lý đa hart trong SPL. |
| `CONFIG_SPL_HAS_CUSTOM_MALLOC_START` | `y` (không có) | SPL sử dụng địa chỉ heap tùy chỉnh. |
| `CONFIG_SPL_CUSTOM_SYS_MALLOC_ADDR` | `0x80700000` (địa chỉ byte) | Địa chỉ bắt đầu heap của SPL. |
| `CONFIG_SPL_SYS_MALLOC` | `y` (không có) | Bật bộ cấp phát động trong SPL. |
| `CONFIG_SPL_SHARES_INIT_SP_ADDR` | `n` (không có) | SPL không dùng chung địa chỉ stack khởi tạo với U-Boot proper. |
| `CONFIG_SPL_RISCV_FIXED_BOOT_HART` | `y` (không có) | Cố định hart thực hiện quá trình boot. |
| `CONFIG_SPL_RISCV_BOOT_HART_ID` | `0` (hart ID) | Hart 0 là hart boot. |
| `CONFIG_SPL_OPENSBI_SCRATCH_OPTIONS` | `0x0` (bitmask) | Không bật tùy chọn scratch đặc biệt khi chuyển quyền cho OpenSBI. |

## Nạp firmware NPU

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_CVA6_SPL_UBOOT_FIT_MAX_SIZE` | `0x00800000` = 8 MiB | Kích thước tối đa dành cho FIT image của U-Boot. |
| `CONFIG_CVA6_SPL_NPU_FIT_ADDR` | `0x82a00000` (địa chỉ byte) | Địa chỉ nạp FIT image chứa firmware NPU. |
| `CONFIG_CVA6_SPL_NPU_FIT_MAX_SIZE` | `0x00800000` = 8 MiB | Kích thước FIT image NPU tối đa. |
| `CONFIG_CVA6_SPL_UBOOT_FIT_FILENAME` | `u-boot.itb` (tên file) | Tên FIT image của U-Boot. |
| `CONFIG_CVA6_SPL_NPU_FIT_FILENAME` | `NPU_fw.itb` (tên file) | Tên FIT image chứa firmware NPU. |
| `CONFIG_SPL_NPU_HANDOFF_BUILD` | `y` (không có) | Xây dựng logic SPL chuyển điều khiển hoặc thông tin cho NPU. |
| `CONFIG_NPU_HANDOFF_BYJUMP_BUILD` | `y` (không có) | Thực hiện handoff NPU bằng thao tác jump. |
| `CONFIG_CVA6_SPL_EMMC_DEVICE` | `0` (device index) | Dùng thiết bị eMMC/MMC số 0 để nạp image. |

## RAM và console trong SPL

| Tên config | Giá trị (đơn vị) | Ý nghĩa |
|---|---|---|
| `CONFIG_SPL_RAM_SUPPORT` | `y` (không có) | Bật hỗ trợ thiết bị RAM trong SPL. |
| `CONFIG_SPL_RAM_DEVICE` | `y` (không có) | Cho phép SPL nạp image từ RAM device. |
| `CONFIG_SPL_ZERO_MEM_BEFORE_USE` | `n` (không có) | Không xóa trắng vùng nhớ trước khi sử dụng. |
| `CONFIG_SPL_SERIAL` | `y` (không có) | Bật serial console trong SPL. |
| `CONFIG_SPL_DM_SERIAL` | `y` (không có) | Serial trong SPL sử dụng Driver Model. |
| `CONFIG_REQUIRE_SERIAL_CONSOLE` | `n` (không có) | Không bắt buộc phải có serial console mới tiếp tục boot. |
| `CONFIG_DEBUG_UART` | `n` (không có) | Tắt UART debug rất sớm. |
| `CONFIG_SIFIVE_SERIAL` | `y` (không có) | Bật driver UART SiFive. |

## Ghi chú

Các dòng `CONFIG_SPL_FIT_SOURCE`, `CONFIG_SPL_SEPARATE_BSS` và `CONFIG_OF_BOARD` đang được comment nên không có hiệu lực.

`CONFIG_SPL_STACK` và `CONFIG_SPL_OPENSBI_LOAD_ADDR` đều có giá trị `0x80200000`. Cách bố trí này thường dựa vào việc stack tăng theo hướng địa chỉ thấp trước khi OpenSBI được nạp hoặc chạy.
