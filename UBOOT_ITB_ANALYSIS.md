# Phân tích itb format

## 1. Kết luận nhanh

File đang được phân tích:

```text
buildroot/output/build/uboot-custom/u-boot.itb
```

Thông tin chính:

| Hạng mục | Trạng thái hiện tại |
|---|---|
| Định dạng image | FIT binary (`.itb`) |
| Kích thước | `754,981 bytes` |
| Kiểu lưu payload | Embedded data |
| Payload | OpenSBI + U-Boot + board DTB |
| SPL load FIT | Đã hỗ trợ và đã bật |
| Hash trong FIT | Chưa có |
| Chữ ký trong FIT | Chưa có |
| Public key trong SPL DTB | Chưa có |
| SPL xác thực chữ ký FIT | Code có hỗ trợ nhưng configuration chưa bật |
| Secure boot hoàn chỉnh | Chưa có |

SPL hiện có thể đọc và load `u-boot.itb`, nhưng mới kiểm tra cấu trúc FIT. SPL chưa xác thực rằng image được phát hành bởi một nguồn tin cậy.

## 2. Phân biệt FIT, ITS và ITB

`FIT` và `ITB` không phải hai định dạng khác nhau.

| Thuật ngữ | Ý nghĩa | Ví dụ |
|---|---|---|
| FIT | Tên định dạng/cơ chế: Flattened Image Tree | “SPL hỗ trợ FIT” |
| ITS | File source dạng text mô tả FIT | `u-boot.its` |
| ITB | FIT đã được build thành binary | `u-boot.itb` |
| `fitImage` | Tên thường dùng cho FIT chứa Linux kernel | `fitImage`, `fitImage.itb` |

Quá trình tạo image:

```text
u-boot.its
    |
    | mkimage -f
    v
u-boot.itb
```

Quan hệ này tương tự Device Tree:

| Device Tree | FIT |
|---|---|
| `.dts` là source | `.its` là source |
| `.dtb` là binary | `.itb` là binary |
| `dtc` compile DTS | `mkimage`/Binman tạo FIT |
| Mô tả phần cứng | Đóng gói firmware, executable và DTB |

Đuôi file chỉ là quy ước. Một FIT binary có thể mang tên `u-boot.itb`, `fitImage` hoặc `firmware.fit`. Magic và cấu trúc bên trong mới quyết định định dạng thật.

## 3. FIT là một FDT đặc biệt

FIT sử dụng định dạng FDT/DTB làm container. Vì vậy `u-boot.itb` hiện tại bắt đầu bằng FDT magic:

```text
0xd00dfeed
```

Cấu trúc tổng quát:

```text
u-boot.itb
|-- FDT header                 40 bytes
|-- Memory reservation map    16 bytes
|-- Structure block
|   |-- FIT metadata
|   |-- U-Boot binary
|   |-- OpenSBI binary
|   `-- Board DTB
|-- Strings block
`-- Padding/không gian dự phòng
```

Ba payload hiện tại:

```text
U-Boot       469,776 bytes
OpenSBI      272,992 bytes
Board DTB     10,189 bytes
----------------------------
Tổng         752,957 bytes
```

Toàn bộ FIT có kích thước `754,981 bytes`. Phần chênh lệch dành cho header, node/property, alignment và padding.

## 4. FDT header vật lý

40 byte đầu của file:

```text
00000000: d00dfeed 000b8525 00000038 000b80bc
00000010: 00000028 00000011 00000002 00000000
00000020: 00000083 000b8084
```

Các số trong FDT header được lưu theo big-endian.

| Tên trường | Giải thích | Giá trị hiện tại |
|---|---|---|
| `magic` | Nhận diện định dạng FDT/FIT; đây không phải chữ ký mật mã | `0xd00dfeed` |
| `totalsize` | Tổng kích thước vùng FIT/FDT mà loader sẽ parse | `0x000b8525` = `754,981 bytes` |
| `off_dt_struct` | Offset bắt đầu structure block | `0x38` = `56` |
| `off_dt_strings` | Offset bắt đầu strings block | `0x000b80bc` = `753,852` |
| `off_mem_rsvmap` | Offset memory reservation map | `0x28` = `40` |
| `version` | Phiên bản định dạng FDT | `17` |
| `last_comp_version` | Phiên bản FDT cũ nhất tương thích | `2` |
| `boot_cpuid_phys` | ID vật lý của boot CPU/hart | `0` |
| `size_dt_strings` | Kích thước strings block | `0x83` = `131 bytes` |
| `size_dt_struct` | Kích thước structure block | `0x000b8084` = `753,796 bytes` |

### 4.1 `magic`

SPL dùng `0xd00dfeed` để nhận biết đầu vào là FDT/FIT. Trường này chỉ nhận diện định dạng; bất kỳ ai cũng có thể tạo một file khác có cùng magic.

### 4.2 `totalsize`

SPL dùng trường này để biết kích thước cần đọc và để kiểm tra FIT có vượt quá vùng QSPI, DDR hoặc buffer cho phép hay không. Nó không cung cấp tính toàn vẹn mật mã.

### 4.3 Structure block

Structure block chứa:

- Tên và quan hệ cha/con của các node.
- Property và giá trị property.
- Binary payload nằm trong property `data`.

Structure block hiện rất lớn vì U-Boot, OpenSBI và board DTB đều được nhúng trực tiếp.

### 4.4 Strings block

Strings block chứa tên property dùng lặp lại, ví dụ:

```text
description
type
os
arch
compression
load
entry
firmware
loadables
fdt
```

Structure block tham chiếu đến các tên này bằng offset để giảm kích thước metadata.

### 4.5 Memory reservation map

Mỗi entry có dạng:

```c
struct {
    uint64_t address;
    uint64_t size;
};
```

Danh sách kết thúc bằng entry `{0, 0}`. FIT hiện tại không khai báo thêm vùng memory reservation nào cho container.

### 4.6 Version

`version = 17` và `last_comp_version = 2` là version của định dạng FDT, không phải version firmware và không thể dùng để chống rollback.

## 5. Toàn bộ node và property của lớp FIT hiện tại

Bảng mục 5 được chia thành ba phần: FDT header vật lý, toàn bộ node/property của cây FIT bên ngoài và các property quan trọng hiện chưa tồn tại.

### 5.1 FDT/FIT header vật lý

| Tên trường | Giải thích | Giá trị hiện tại |
|---|---|---|
| `magic` | Giá trị nhận diện một FDT/FIT hợp lệ ở đầu file. Đây chỉ là magic định dạng, không phải chữ ký mật mã | `0xd00dfeed` |
| `totalsize` | Tổng kích thước vùng FDT/FIT tính từ byte đầu header; SPL dùng để giới hạn vùng parse và vùng đọc | `0x000b8525` = `754,981 bytes` |
| `off_dt_struct` | Offset tính từ đầu file tới structure block chứa node, property và embedded payload | `0x00000038` = `56 bytes` |
| `off_dt_strings` | Offset tính từ đầu file tới strings block chứa tên các property | `0x000b80bc` = `753,852 bytes` |
| `off_mem_rsvmap` | Offset tính từ đầu file tới memory reservation map | `0x00000028` = `40 bytes` |
| `version` | Phiên bản định dạng FDT mà file đang sử dụng; không phải phiên bản firmware | `0x00000011` = `17` |
| `last_comp_version` | Phiên bản FDT cũ nhất mà file vẫn tương thích | `0x00000002` = `2` |
| `boot_cpuid_phys` | Physical ID của boot CPU/hart được ghi trong FDT header | `0x00000000` = `0` |
| `size_dt_strings` | Kích thước strings block | `0x00000083` = `131 bytes` |
| `size_dt_struct` | Kích thước structure block; lớn vì chứa cả U-Boot, OpenSBI và board DTB dưới dạng embedded data | `0x000b8084` = `753,796 bytes` |
| `mem_rsvmap[0].address` | Địa chỉ của entry kết thúc memory reservation map | `0x0000000000000000` |
| `mem_rsvmap[0].size` | Kích thước của entry kết thúc memory reservation map; cặp `{0, 0}` cho biết không còn entry nào | `0x0000000000000000` |
| `FDT header size` | Kích thước cố định của mười trường FDT header ở trên | `40 bytes` = `0x28` |
| `FDT structure start` | Vị trí bắt đầu structure block sau header và reservation terminator | Offset `0x38` |
| `FIT file size` | Kích thước thực của `u-boot.itb` hiện tại, trùng với `totalsize` | `754,981 bytes` |

Raw header tương ứng:

```text
00000000: d00dfeed 000b8525 00000038 000b80bc
00000010: 00000028 00000011 00000002 00000000
00000020: 00000083 000b8084
```

### 5.2 Toàn bộ node và property của cây FIT bên ngoài

Bảng dưới đây liệt kê đầy đủ các node và property của **cây FIT bên ngoài** trong `u-boot.itb`. Nội dung hàng trăm nghìn byte của các property `data` được biểu diễn bằng tên nguồn và kích thước thay vì in toàn bộ byte.

`/images/fdt-1/data` bản thân là một DTB phần cứng có cây node riêng. Cây phần cứng đó là payload của FIT, không phải metadata của lớp FIT, nên không được bung ra trong bảng này.

| Đường dẫn đầy đủ | Loại | Giải thích | Giá trị hiện tại |
|---|---|---|---|
| `/` | Node | Root của FIT container | Chứa `timestamp`, `description`, `#address-cells`, `images` và `configurations` |
| `/timestamp` | `u32` | UNIX timestamp do Binman/mkimage ghi khi tạo FIT; không phải firmware version | `0x6aa9439c` = `2026-09-15 20:09:48 +0700` |
| `/description` | String | Mô tả mục đích của toàn bộ FIT | `"Configuration to load OpenSBI before U-Boot"` |
| `/#address-cells` | `u32` | Số cell 32-bit dùng để biểu diễn một địa chỉ trong FIT | `<2>`; địa chỉ được biểu diễn bằng 64 bit |
| `/images` | Node | Container chứa toàn bộ image/payload | Có ba node con: `uboot`, `opensbi`, `fdt-1` |
| `/images/uboot` | Node | Mô tả U-Boot proper được SPL load | Image số 0 |
| `/images/uboot/description` | String | Tên hiển thị của image | `"U-Boot"` |
| `/images/uboot/type` | String | Phân loại payload là chương trình độc lập | `"standalone"` |
| `/images/uboot/os` | String | Loại OS/firmware mà image framework gán cho payload | `"U-Boot"` |
| `/images/uboot/arch` | String | Kiến trúc CPU của binary | `"riscv"` |
| `/images/uboot/compression` | String | Kiểu nén; SPL không cần giải nén payload | `"none"` |
| `/images/uboot/load` | Hai cell `u32` | Địa chỉ RAM 64-bit mà SPL copy U-Boot tới | `<0x00000000 0x80200000>` = `0x0000000080200000` |
| `/images/uboot/data` | Byte array | Nội dung `u-boot-nodtb.bin` được nhúng trực tiếp trong FIT structure | `469,776 bytes` = `458.77 KiB` |
| `/images/opensbi` | Node | Mô tả OpenSBI `fw_dynamic.bin` | Image số 1 |
| `/images/opensbi/description` | String | Tên hiển thị của image | `"OpenSBI fw_dynamic Firmware"` |
| `/images/opensbi/type` | String | Phân loại payload là firmware | `"firmware"` |
| `/images/opensbi/os` | String | Loại firmware được image framework nhận diện | `"opensbi"` |
| `/images/opensbi/arch` | String | Kiến trúc CPU của binary | `"riscv"` |
| `/images/opensbi/compression` | String | Kiểu nén; SPL không cần giải nén payload | `"none"` |
| `/images/opensbi/load` | Hai cell `u32` | Địa chỉ RAM 64-bit mà SPL copy OpenSBI tới | `<0x00000000 0x80000000>` = `0x0000000080000000` |
| `/images/opensbi/entry` | Hai cell `u32` | Địa chỉ bắt đầu thực thi OpenSBI sau khi SPL load xong các image | `<0x00000000 0x80000000>` = `0x0000000080000000` |
| `/images/opensbi/data` | Byte array | Nội dung `fw_dynamic.bin` được nhúng trực tiếp trong FIT structure | `272,992 bytes` = `266.59 KiB` |
| `/images/fdt-1` | Node | Mô tả Device Tree của board được truyền cho boot stage tiếp theo | Image số 2 |
| `/images/fdt-1/description` | String | Tên cấu hình phần cứng của board | `"viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig"` |
| `/images/fdt-1/type` | String | Phân loại payload là Flattened Device Tree | `"flat_dt"` |
| `/images/fdt-1/compression` | String | Kiểu nén; DTB không được nén | `"none"` |
| `/images/fdt-1/offset` | `u32` | Metadata vị trí do Binman thêm; không dùng để tìm payload khi property `data` đang tồn tại | `<0>` |
| `/images/fdt-1/size` | `u32` | Metadata kích thước của Binman; không phải kích thước thực của property `data` trong image hiện tại | `<0>` |
| `/images/fdt-1/image-pos` | `u32` | Metadata absolute image position của Binman | `<0>` |
| `/images/fdt-1/data` | Byte array | Board DTB được nhúng trực tiếp trong FIT structure | `10,189 bytes` = `9.95 KiB` |
| `/configurations` | Node | Container mô tả cách kết hợp các image thành một boot configuration | Có property `default` và node con `conf-1` |
| `/configurations/default` | String | Tên configuration được chọn khi loader không yêu cầu configuration khác | `"conf-1"` |
| `/configurations/conf-1` | Node | Boot configuration duy nhất và là configuration mặc định | Liên kết `opensbi`, `uboot` và `fdt-1` |
| `/configurations/conf-1/description` | String | Tên board/configuration | `"viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig"` |
| `/configurations/conf-1/firmware` | String tham chiếu tên | Chọn primary firmware; SPL sẽ handoff vào image này | `"opensbi"` → `/images/opensbi` |
| `/configurations/conf-1/loadables` | String list | Danh sách image phụ SPL phải load trước khi handoff | `"uboot"` → `/images/uboot` |
| `/configurations/conf-1/fdt` | String tham chiếu tên | Chọn Device Tree dùng cho configuration | `"fdt-1"` → `/images/fdt-1` |

### 5.3 Các property quan trọng không tồn tại trong FIT hiện tại

Các hàng sau không phải property đang có trong file; chúng được liệt kê để chỉ rõ những thông tin mà image hiện tại còn thiếu.

| Property/node vắng mặt | Vị trí đáng lẽ xuất hiện | Ý nghĩa | Trạng thái hiện tại |
|---|---|---|---|
| `entry` | `/images/uboot/entry` | Entry point để loader nhảy trực tiếp vào U-Boot | Không có; OpenSBI là primary firmware và handoff sang U-Boot |
| `load` | `/images/fdt-1/load` | Địa chỉ RAM cố định cho DTB | Không có; SPL tự chọn/ghi nhận địa chỉ FDT |
| `arch` | `/images/fdt-1/arch` | Kiến trúc gắn với DTB | Không có |
| `hash-*` | Dưới mỗi node `/images/*` | Lưu hash để kiểm tra tính toàn vẹn từng payload | Không có ở cả ba image |
| `signature-*` | Dưới `/images/*` | Chữ ký riêng cho từng image | Không có |
| `signature-*` | Dưới `/configurations/conf-1` | Chữ ký ràng buộc configuration với OpenSBI, U-Boot và DTB | Không có |
| `data-offset` | Dưới `/images/*` | Offset payload kiểu external-data tính từ cuối FIT structure | Không có vì FIT đang dùng embedded data |
| `data-position` | Dưới `/images/*` | Vị trí tuyệt đối của external payload | Không có vì FIT đang dùng embedded data |
| `data-size` | Dưới `/images/*` | Kích thước external payload | Không có vì kích thước đã nằm trong property `data` |

## 6. Dạng cây của FIT hiện tại

Đã lược bỏ nội dung binary trong các property `data`:

```dts
/ {
    timestamp = <0x6aa9439c>;
    description = "Configuration to load OpenSBI before U-Boot";
    #address-cells = <2>;

    images {
        uboot {
            description = "U-Boot";
            type = "standalone";
            os = "U-Boot";
            arch = "riscv";
            compression = "none";
            load = <0x0 0x80200000>;
            data = <...469776 bytes...>;
        };

        opensbi {
            description = "OpenSBI fw_dynamic Firmware";
            type = "firmware";
            os = "opensbi";
            arch = "riscv";
            compression = "none";
            load = <0x0 0x80000000>;
            entry = <0x0 0x80000000>;
            data = <...272992 bytes...>;
        };

        fdt-1 {
            description =
                "viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig";
            type = "flat_dt";
            compression = "none";
            data = <...10189 bytes...>;
        };
    };

    configurations {
        default = "conf-1";

        conf-1 {
            description =
                "viettel/chipyardharnessViettelDualSSV2DDR2GBFPGAConfig";
            firmware = "opensbi";
            loadables = "uboot";
            fdt = "fdt-1";
        };
    };
};
```

## 7. Ý nghĩa của các image

### 7.1 U-Boot

U-Boot proper được nhúng dưới node `/images/uboot`. SPL copy nó tới `0x80200000`.

Node này không có property `entry`, vì SPL không chạy U-Boot trực tiếp. OpenSBI là firmware chính và sẽ thực hiện handoff sang U-Boot.

### 7.2 OpenSBI

OpenSBI được nhúng dưới `/images/opensbi` và được chọn bởi:

```dts
firmware = "opensbi";
```

SPL copy OpenSBI tới `0x80000000`, sau đó nhảy vào cùng địa chỉ này.

### 7.3 Board DTB

`fdt-1` mô tả phần cứng của board, bao gồm CPU/hart, memory, UART, SPI, interrupt controller, clock và các peripheral khác.

Node không có địa chỉ `load` cố định. SPL chọn vùng nhớ phù hợp và lưu kết quả trong `spl_image->fdt_addr`.

### 7.4 Configuration

`conf-1` liên kết ba thành phần:

```text
firmware  -> opensbi
loadables -> uboot
fdt       -> fdt-1
```

Nhờ configuration, FIT có thể chứa nhiều firmware hoặc DTB và chọn đúng tổ hợp khi boot.

## 8. Boot flow hiện tại

```text
SPL
 |
 |-- Đọc FDT header
 |   |-- kiểm tra magic
 |   |-- kiểm tra totalsize
 |   `-- kiểm tra cấu trúc FIT
 |
 |-- Chọn configuration "conf-1"
 |
 |-- Load OpenSBI
 |   |-- source: /images/opensbi/data
 |   |-- destination: 0x80000000
 |   `-- entry: 0x80000000
 |
 |-- Load U-Boot
 |   |-- source: /images/uboot/data
 |   `-- destination: 0x80200000
 |
 |-- Load fdt-1
 |
 |-- Chuẩn bị OpenSBI dynamic information
 |
 `-- Jump 0x80000000
     |
     `-- OpenSBI
         |
         `-- Handoff U-Boot tại 0x80200000
```

## 9. Embedded-data FIT và external-data FIT

Có hai cách bố trí payload phổ biến.

| Kiểu FIT | Metadata | Payload | Property nhận diện |
|---|---|---|---|
| Embedded-data FIT | Trong FDT/FIT | Nhúng trực tiếp trong structure block | `data` |
| External-data FIT | Trong FDT/FIT | Nằm ngoài FDT structure, thường nối sau metadata trong cùng file | `data-offset` hoặc `data-position`, kèm `data-size` |

### 9.1 Embedded-data FIT

```dts
images {
    uboot {
        load = <0x0 0x80200000>;
        data = <toàn bộ binary U-Boot>;
    };
};
```

Đặc điểm:

- Metadata và payload nằm trong cây FDT.
- Dễ tạo và parse.
- Structure block lớn.
- `u-boot.itb` hiện tại thuộc loại này.

### 9.2 External-data FIT

```dts
images {
    uboot {
        load = <0x0 0x80200000>;
        data-offset = <0x...>;
        data-size = <469776>;
    };
};
```

Hoặc:

```dts
data-position = <0x...>;
data-size = <469776>;
```

Payload không nằm trong property `data`, nhưng thường vẫn được nối phía sau metadata trong cùng file `.itb`.

Do đó không nên gọi external-data FIT là “ITB không chứa payload”. Cách gọi chính xác là:

```text
Embedded FIT: payload nằm trong FDT structure.
External FIT: payload nằm ngoài FDT structure.
```

Nếu chỉ có metadata mà external payload không tồn tại trong file hoặc storage tại vị trí được chỉ định, image không thể boot độc lập.

## 10. Trạng thái hỗ trợ Secure Boot của SPL

U-Boot source hiện tại có hỗ trợ xác thực chữ ký FIT trong SPL. Code xác thực đã có sẵn trong:

```text
common/spl/spl_fit.c
```

SPL có thể:

- Kiểm tra hash của từng image.
- Xác thực chữ ký của selected configuration.
- Sử dụng public key được lưu trong SPL control DTB.
- Từ chối FIT bị sửa hoặc được ký bằng key không tin cậy.

Tuy nhiên configuration hiện tại chỉ bật:

```config
CONFIG_SPL_LOAD_FIT=y
```

Các chức năng xác thực chưa được bật:

```config
# CONFIG_FIT_SIGNATURE is not set
# CONFIG_SPL_FIT_SIGNATURE is not set
# CONFIG_RSA is not set
# CONFIG_ECDSA is not set
```

Ngoài ra:

- `u-boot.itb` chưa có node `hash`.
- `u-boot.itb` chưa có node `signature`.
- `spl/u-boot-spl.dtb` chưa có `/signature` chứa public key.

Vì vậy hiện tại SPL chỉ kiểm tra FIT có đúng cấu trúc hay không, chưa xác thực nguồn gốc image.

## 11. Header hiện tại không phải security header

Các trường như:

```text
magic
totalsize
load
entry
firmware
loadables
```

chỉ là metadata. Chúng không được bảo vệ mật mã trong image hiện tại.

`fit_check_format()` có thể phát hiện một FIT hỏng cấu trúc, nhưng không thể chứng minh rằng FIT do nhà sản xuất tin cậy tạo ra.

Những thành phần hiện có thể bị thay đổi mà chưa bị phát hiện bằng chữ ký:

- OpenSBI binary.
- U-Boot binary.
- Board DTB.
- Địa chỉ `load` và `entry`.
- Configuration mặc định.
- Liên kết `firmware`, `loadables` và `fdt`.
- Timestamp và description.

## 12. Cấu trúc signed FIT được đề xuất

Nên dùng khả năng signed FIT có sẵn thay vì prepend một custom header phía trước ITB:

```text
FIT header
|-- images/opensbi + SHA-256 hash
|-- images/uboot   + SHA-256 hash
|-- images/fdt-1   + SHA-256 hash
`-- configurations/conf-1
    `-- RSA-2048 signature bảo vệ opensbi + uboot + fdt-1
```

Ví dụ mỗi image có hash:

```dts
hash-1 {
    algo = "sha256";
};
```

Configuration có chữ ký:

```dts
signature-1 {
    algo = "sha256,rsa2048";
    key-name-hint = "prod";
    sign-images = "firmware", "loadables", "fdt";
};
```

Public key tương ứng phải được nhúng trong SPL DTB và đánh dấu bắt buộc:

```dts
/ {
    signature {
        key-prod {
            key-name-hint = "prod";
            algo = "sha256,rsa2048";
            required = "conf";
            /* RSA public-key parameters */
        };
    };
};
```

`required = "conf"` rất quan trọng. Nếu không có required key, việc bật code FIT signature chưa chắc buộc SPL từ chối tất cả FIT không ký.

## 13. Các configuration cần bật

Tối thiểu cần xem xét:

```config
CONFIG_SPL_FIT_SIGNATURE=y
CONFIG_SPL_RSA=y
CONFIG_SPL_RSA_VERIFY=y
CONFIG_SPL_FIT_SIGNATURE_MAX_SIZE=0x00200000
```

`CONFIG_SPL_FIT_SIGNATURE` cũng kéo theo các thành phần FIT full check, crypto, hash và image-sign-info cần thiết. Sau khi bật phải kiểm tra lại kích thước SPL so với:

```config
CONFIG_SPL_MAX_SIZE=0x40000
```

Private key chỉ được sử dụng trên signing server/build environment. Không được nhúng private key vào firmware hoặc commit vào repository.

## 14. Signed FIT và custom security header

Loader hiện tại kỳ vọng FDT magic nằm ngay byte đầu của `u-boot.itb`. DDR loader gọi `fit_check_format()` trực tiếp tại địa chỉ bắt đầu FIT.

Nếu prepend một custom header:

```text
Custom security header
FIT/ITB
```

thì byte đầu không còn là `0xd00dfeed`. Loader DDR, eMMC và QSPI phải được sửa để:

1. Đọc custom header.
2. Kiểm tra magic, version và kích thước của custom header.
3. Xác thực chữ ký của header và payload.
4. Tính offset tới FDT/FIT thực sự.
5. Truyền đúng offset cho FIT loader.

Nếu không có yêu cầu định dạng bắt buộc từ BootROM hoặc kiến trúc hệ thống, signed FIT chuẩn của U-Boot đơn giản và ít rủi ro hơn custom header.

## 15. Chuỗi tin cậy hoàn chỉnh

SPL xác thực `u-boot.itb` mới chỉ tạo ra verified boot từ SPL trở đi:

```text
BootROM/FSBL
    |
    v
SPL chứa trusted public key
    |
    | verify signed u-boot.itb
    v
OpenSBI + U-Boot + DTB
```

Để thành secure boot chain hoàn chỉnh, BootROM hoặc boot stage trước đó cũng phải xác thực SPL. Nếu attacker có thể thay cả SPL và public key bên trong SPL, họ có thể loại bỏ bước xác thực FIT.

Root of trust nên nằm trong một vùng không thể bị attacker thay đổi, ví dụ:

- Public-key hash trong eFuse/OTP.
- BootROM không thể sửa.
- SPL được BootROM xác thực bằng hardware root key.

Nếu cần chống rollback, ngoài chữ ký còn phải có firmware version được ký và monotonic counter lưu trong eFuse, OTP hoặc secure storage.

## 16. Kiểm thử bắt buộc sau khi bật chữ ký

| Trường hợp | Kết quả mong đợi |
|---|---|
| FIT hợp lệ và ký đúng key | Boot thành công |
| Sửa một byte U-Boot | SPL từ chối |
| Sửa một byte OpenSBI | SPL từ chối |
| Sửa một byte DTB | SPL từ chối |
| Sửa `load` hoặc `entry` | SPL từ chối |
| Xóa signature | SPL từ chối |
| Ký bằng key khác | SPL từ chối |
| Thay configuration | SPL từ chối |
| FIT vượt kích thước cho phép | SPL từ chối |
| Image cũ nhưng chữ ký hợp lệ | Chỉ bị từ chối nếu đã triển khai anti-rollback |

## 17. Các lệnh kiểm tra hữu ích

Liệt kê nội dung FIT:

```bash
buildroot/output/host/bin/mkimage \
    -l buildroot/output/build/uboot-custom/u-boot.itb
```

Đọc 40 byte header:

```bash
xxd -g 4 -l 40 \
    buildroot/output/build/uboot-custom/u-boot.itb
```

Liệt kê node cấp cao nhất:

```bash
buildroot/output/host/bin/fdtget -l \
    buildroot/output/build/uboot-custom/u-boot.itb /
```

Liệt kê property của U-Boot image:

```bash
buildroot/output/host/bin/fdtget -p \
    buildroot/output/build/uboot-custom/u-boot.itb \
    /images/uboot
```

Kiểm tra public-key node trong SPL DTB:

```bash
buildroot/output/host/bin/fdtget -l \
    buildroot/output/build/uboot-custom/spl/u-boot-spl.dtb \
    /signature
```
