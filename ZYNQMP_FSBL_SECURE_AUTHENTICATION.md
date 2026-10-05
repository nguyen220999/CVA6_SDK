# Zynq UltraScale+ MPSoC FSBL Secure Authentication

## 1. Phạm vi

Tài liệu này mô tả luồng kiểm tra và xác thực ảnh boot trong project
`zynqmp_fsbl_hello_work`, tập trung vào các partition được FSBL nạp sau khi
FSBL bắt đầu chạy. Nội dung chính gồm:

- vai trò của CSU BootROM, FSBL và CSU crypto hardware;
- cấu trúc Partition Header và Authentication Certificate;
- vị trí của payload và certificate trong bộ nhớ;
- trình tự SHA3/RSA trước khi handoff;
- cách bảo vệ entry point;
- trạng thái secure của bản build hiện tại.

## 2. Kết luận nhanh

Đối với một partition dành cho CPU và có RSA authentication, FSBL thực hiện:

```text
Boot device (QSPI/SD/eMMC)
        |
        +-- Partition Header --> cấu trúc quản lý của FSBL
        |
        +-- Payload -----------> DestinationLoadAddress trong DDR/TCM
        |
        `-- Auth Certificate --> AuthBuffer trong OCM

FSBL:
  1. kiểm tra Partition Header;
  2. copy payload vào RAM;
  3. copy Authentication Certificate vào AuthBuffer;
  4. dùng CSU DMA + SHA3 để hash payload và phần certificate được ký;
  5. dùng CSU RSA để xử lý chữ ký;
  6. so sánh digest;
  7. chỉ tạo handoff entry và chạy firmware khi xác thực thành công.
```

Payload chưa xác thực có thể đã nằm trong DDR/TCM, nhưng CPU đích chưa được
release/handoff nên payload chưa được thực thi.

## 3. Chuỗi tin cậy

### 3.1 Xác thực chính FSBL

Khi Secure Boot được bật, CSU BootROM xác thực FSBL trước khi cho FSBL chạy:

```text
Power-on
  -> immutable CSU BootROM
  -> SHA3-384 và RSA-4096 hardware
  -> PPK hash trong eFUSE
  -> FSBL được phép thực thi
```

Đây là Hardware Root of Trust. RoT không phải là một application CPU riêng.
Nó gồm BootROM bất biến, eFUSE/key state và các crypto engine trong CSU.

### 3.2 Xác thực các partition sau FSBL

FSBL chạy trên A53 hoặc R5 và điều phối quá trình. Các phép SHA3/RSA nặng được
thực hiện bằng phần cứng CSU qua thư viện XSecure và CSU DMA.

Source xác nhận điều này trong
`zynqmp_fsbl_hello_work/src/xfsbl_rsa_sha.c`:

```c
/* For SHA3 CSU h/w will be used. */
/* For RSA-4096 we will always use CSU h/w. */
```

CSU không tự hiểu cấu trúc partition và không tự quyết định handoff. FSBL chọn
buffer, chiều dài, public key, signature, gọi các primitive SHA/RSA và xử lý
kết quả trả về.

## 4. Trình tự load, verify và handoff

Luồng chính nằm trong `XFsbl_PartitionLoad()` tại
`zynqmp_fsbl_hello_work/src/xfsbl_partition_load.c`:

```c
Status = XFsbl_PartitionHeaderValidation(...);
Status = XFsbl_PartitionCopy(...);
Status = XFsbl_PartitionValidation(...);
```

Tức là thứ tự cho partition CPU thông thường là:

```text
validate header -> copy vào RAM -> authenticate/checksum -> handoff
```

`XFsbl_PartitionCopy()` copy payload bằng:

```c
Status = FsblInstancePtr->DeviceOps.DeviceCopy(
    SrcAddress, LoadAddress, Length);
```

Sau đó `XFsbl_PartitionValidation()` gọi:

```c
Status = XFsbl_Authentication(
    FsblInstancePtr,
    LoadAddress,
    Length,
    (PTRSIZE)AuthBuffer,
    PartitionNum);
```

Chỉ khi `XFsbl_PartitionValidation()` thành công, FSBL mới thêm
`DestinationExecutionAddress` vào `HandoffValues`. Stage 4 sau đó mới gọi
`XFsbl_Handoff()`.

## 5. Partition Header chứa gì?

`XFsblPs_PartitionHeader` có kích thước 64 byte và được định nghĩa trong
`zynqmp_fsbl_hello_work/src/xfsbl_image_header.h`.

| Offset | Field | Ý nghĩa |
|---:|---|---|
| `0x00` | `EncryptedDataWordLength` | Kích thước dữ liệu mã hóa, đơn vị word 32-bit |
| `0x04` | `UnEncryptedDataWordLength` | Kích thước payload sau giải mã |
| `0x08` | `TotalDataWordLength` | Tổng kích thước, gồm Authentication Certificate nếu có |
| `0x0C` | `NextPartitionOffset` | Offset tới Partition Header tiếp theo |
| `0x10` | `DestinationExecutionAddress` | Entry point dùng khi handoff |
| `0x18` | `DestinationLoadAddress` | Địa chỉ DDR/TCM nhận payload |
| `0x20` | `DataWordOffset` | Offset tới payload trong boot image |
| `0x24` | `PartitionAttributes` | Các thuộc tính của partition |
| `0x28` | `SectionCount` | Số section |
| `0x2C` | `ChecksumWordOffset` | Offset tới SHA3 checksum nếu được bật |
| `0x30` | `ImageHeaderOffset` | Offset tới Image Header tương ứng |
| `0x34` | `AuthCertificateOffset` | Offset tới Authentication Certificate |
| `0x38` | `Iv` | Giá trị điều chỉnh IV cho AES |
| `0x3C` | `Checksum` | Checksum của chính Partition Header |

Các trường có tên `WordLength` hoặc `WordOffset` dùng đơn vị word 32-bit và
thường được nhân với 4 trước khi dùng làm byte address/length.

### 5.1 PartitionAttributes

```text
bit 23       Vector location
bits 22:20   Authentication block size
bit 18       Endianness
bits 17:16   Partition owner
bit 15       RSA signature present
bits 14:12   Checksum type: none hoặc SHA3
bits 11:8    Destination CPU
bit 7        Encryption enabled
bits 6:4     Destination device: PS, PL hoặc PMU
bit 3        A53 execution state: AArch32/AArch64
bits 2:1     Target exception level
bit 0        TrustZone secure/non-secure
```

Partition Header không chứa trực tiếp payload, payload hash hoặc RSA
signature. Nó chứa offset chỉ tới các đối tượng đó:

```text
DataWordOffset              -> payload
ChecksumWordOffset          -> SHA3 checksum 48 byte
AuthCertificateOffset       -> keys và signatures
DestinationLoadAddress      -> nơi copy payload
DestinationExecutionAddress -> nơi bắt đầu thực thi
```

## 6. Authentication Certificate

Trong source hiện tại, kích thước tối thiểu của certificate là `0xEC0` byte
(3776 byte):

| Offset | Nội dung | Kích thước |
|---:|---|---:|
| `0x000` | Authentication header, SPK ID và user data | 64 byte |
| `0x040` | PPK: modulus, extension và exponent/padding | 1088 byte |
| `0x480` | SPK: modulus, extension và exponent/padding | 1088 byte |
| `0x8C0` | SPK signature | 512 byte |
| `0xAC0` | Boot Header signature | 512 byte |
| `0xCC0` | Partition/header-region signature | 512 byte |

Ý nghĩa của signature cuối phụ thuộc certificate đang bảo vệ header region hay
một data partition.

## 7. Payload và certificate được đặt ở đâu?

Đối với authenticated non-PL partition, `XFsbl_PartitionCopy()` tách
certificate ra khỏi payload:

```c
Length = PartitionHeader->TotalDataWordLength * 4U;
Length = Length - XFSBL_AUTH_CERT_MIN_SIZE;

DeviceCopy(SrcAddress + Length,
           (INTPTR)AuthBuffer,
           XFSBL_AUTH_CERT_MIN_SIZE);

DeviceCopy(SrcAddress,
           LoadAddress,
           Length);
```

Kết quả:

```text
DDR/TCM tại LoadAddress: payload/code
OCM tại AuthBuffer:      Authentication Certificate
```

`AuthBuffer` là global buffer của FSBL. Với linker layout thông thường của
FSBL, buffer này nằm trong OCM cùng vùng dữ liệu của FSBL.

## 8. Dữ liệu nào được đưa vào SHA3?

Trong `XFsbl_PartitionSignVer()`, FSBL bắt đầu một SHA context rồi đưa hai vùng
dữ liệu vào tuần tự:

```c
XFsbl_ShaStart(...);

XFsbl_ShaUpdate(...,
    (u8 *)PartitionOffset,
    HashDataLen,
    HashLen);

XFsbl_ShaUpdate(...,
    (u8 *)AcOffset,
    XFSBL_AUTH_CERT_MIN_SIZE - XFSBL_FSBL_SIG_SIZE,
    HashLen);

XFsbl_ShaFinish(..., PartitionHash, HashLen);
```

Trong đó:

- `PartitionOffset` là `LoadAddress` của payload trong DDR/TCM;
- `AcOffset` là địa chỉ `AuthBuffer` trong OCM;
- 512 byte signature cuối certificate không được đưa vào chính hash mà nó ký.

Kết quả tương đương:

```text
PartitionHash =
    SHA3(payload || authentication_certificate_without_final_signature)
```

FSBL không gửi hai địa chỉ trong một lệnh duy nhất. Nó gọi hai lần
`XSecure_Sha3Update()`. Driver cấu hình CSU DMA đọc lần lượt hai vùng, trong khi
CSU SHA3 giữ cùng internal hash state giữa hai lần update.

## 9. RSA signature verification

Sau khi có `PartitionHash`, FSBL lấy SPK modulus/exponent và partition signature
từ `AuthBuffer`, sau đó gọi:

```c
XSecure_RsaInitialize(...);
XSecure_RsaPublicEncrypt(..., PartitionSignature, ..., RsaResult);
XSecure_RsaSignVerification(RsaResult, PartitionHash, HashLen);
```

Luồng logic:

```text
CSU SHA3(payload + protected certificate fields) -> CalculatedHash

CSU RSA(partition signature, SPK public key)      -> SignedHash

FSBL/XSecure: CalculatedHash == SignedHash ?
```

Nếu không bằng nhau, `XFsbl_PartitionLoad()` trả lỗi và không đi tới handoff.

## 10. Entry point được bảo vệ như thế nào?

`DestinationExecutionAddress` nằm trong Partition Header, không nằm trong
payload. Vì vậy chỉ ký payload là chưa đủ: một attacker có thể giữ payload hợp
lệ nhưng sửa entry point để CPU nhảy vào vị trí khác.

ZynqMP giải quyết việc này bằng một authentication certificate riêng cho vùng
header. Trong `XFsbl_ValidateHeader()`:

```c
Size = (AcOffset * 4U) - ImageHeaderTableAddressOffset;

DeviceCopy(..., ImageHdr, Size);

Status = XFsbl_Authentication(
    FsblInstancePtr,
    (PTRSIZE)ImageHdr,
    Size + XFSBL_AUTH_CERT_MIN_SIZE,
    (PTRSIZE)AuthBuffer,
    0U);
```

Vùng được xác thực gồm Image Header Table, Image Headers và Partition Headers.
Sau khi xác thực thành công, FSBL mới gọi `XFsbl_ReadImageHeader()` và sử dụng
các trường `DestinationLoadAddress`/`DestinationExecutionAddress`.

Do đó có hai lớp chữ ký:

```text
Header authentication:
  bảo vệ entry point, load address, size, CPU/device đích và các offset

Partition authentication:
  bảo vệ payload/code và certificate liên quan
```

## 11. Checksum SHA3 không có RSA

Nếu partition chỉ dùng `checksum = SHA3`, FSBL thực hiện:

```text
copy payload vào RAM
-> CSU SHA3(payload)
-> đọc expected hash 48 byte tại ChecksumWordOffset
-> so sánh từng byte
-> thành công thì tiếp tục
```

Checksum SHA3 phát hiện dữ liệu bị thay đổi nhưng không chứng minh nguồn gốc,
vì attacker có thể thay payload và tạo lại SHA3. RSA authentication mới cung
cấp authenticity khi private signing key được bảo vệ đúng cách.

Checksum cộng trong trường `PartitionHeader.Checksum` chỉ bảo vệ lỗi ngẫu nhiên
của 64 byte Partition Header. Nó không phải cơ chế chống giả mạo.

## 12. Bitstream dành cho PL

Authenticated bitstream không dùng hoàn toàn cùng luồng với CPU partition.
`XFsbl_SecPlPartition()` xử lý bitstream theo block:

```text
flash hoặc temporary DDR
  -> authenticate block
  -> re-authenticate từng chunk khi sử dụng
  -> chunk hợp lệ mới được gửi qua CSU DMA/AES/PCAP vào PL
```

Mục đích của re-authentication là tránh việc dữ liệu thay đổi giữa thời điểm
kiểm tra và thời điểm gửi tới PCAP.

## 13. Trạng thái secure của project hiện tại

Trong `zynqmp_fsbl_hello_work/src/xfsbl_config.h`:

```c
#define FSBL_SECURE_EXCLUDE_VAL (1U)
```

Giá trị này sinh `FSBL_SECURE_EXCLUDE`, vì vậy `XFSBL_SECURE` không được định
nghĩa. Hệ quả:

- checksum của Image Header Table và Partition Header vẫn được kiểm tra;
- payload SHA3 checksum vẫn có thể chạy nếu BOOT.BIN yêu cầu;
- RSA authentication và AES secure partition bị loại khỏi binary;
- authenticated/encrypted boot image sẽ gặp
  `XFSBL_ERROR_SECURE_NOT_ENABLED` thay vì được handoff.

`xfsbl_authentication.c` vẫn có trong danh sách source build, nhưng phần
implementation được bao bởi `#ifdef XFSBL_SECURE`, nên việc thấy file được
compile không đồng nghĩa RSA code có trong ELF.

Early handoff cũng đang bị tắt:

```c
#define FSBL_EARLY_HANDOFF_EXCLUDE_VAL (1U)
```

Vì vậy với cấu hình hiện tại, FSBL đi tới handoff thông thường sau khi các
partition thuộc quyền FSBL đã được load/validate.

## 14. Muốn bật secure authentication

Ở mức source, cần build FSBL với secure feature được include, ví dụ đặt:

```c
#define FSBL_SECURE_EXCLUDE_VAL (0U)
```

Sau đó phải tạo boot image đúng định dạng bằng Bootgen, gồm header
authentication và partition authentication certificates phù hợp. Việc chỉ bật
macro trong FSBL nhưng dùng BOOT.BIN không có certificate sẽ không tạo ra một
secure boot chain.

Không nên provision/burn RSA eFUSE trước khi đã kiểm tra hoàn chỉnh keys,
certificates, BOOT.BIN và recovery flow trên thiết bị thử nghiệm; eFUSE là thay
đổi không thể đảo ngược.

## 15. Bản đồ source quan trọng

| Chức năng | File/hàm |
|---|---|
| State machine load và handoff | `xfsbl_main.c`: `XFsbl_PartitionLoad()`, `XFsbl_Handoff()` |
| Parse/validate header | `xfsbl_initialization.c`: `XFsbl_ValidateHeader()` |
| Partition copy/validation | `xfsbl_partition_load.c`: `XFsbl_PartitionCopy()`, `XFsbl_PartitionValidation()` |
| Header definitions | `xfsbl_image_header.h`: `XFsblPs_PartitionHeader` |
| RSA authentication | `xfsbl_authentication.c`: `XFsbl_Authentication()` |
| Partition signature | `xfsbl_authentication.c`: `XFsbl_PartitionSignVer()` |
| CSU SHA3 wrapper | `xfsbl_rsa_sha.c`: `XFsbl_ShaStart/Update/Finish()` |
| Secure PL partition | `xfsbl_plpartition_valid.c`: `XFsbl_SecPlPartition()` |
| Feature configuration | `xfsbl_config.h`, `xfsbl_hw.h` |

## 16. Tài liệu AMD tham khảo

- [Zynq UltraScale+ MPSoC Software Developer Guide (UG1137) - Authentication](https://docs.amd.com/r/en-US/ug1137-zynq-ultrascale-mpsoc-swdev/Authentication)
- [UG1137 - Configuration Security Unit](https://docs.amd.com/r/en-US/ug1137-zynq-ultrascale-mpsoc-swdev/Configuration-Security-Unit-CSU)
- [Bootgen User Guide (UG1283) - Zynq UltraScale+ Authentication Certificates](https://docs.amd.com/r/en-US/ug1283-bootgen-user-guide/Zynq-UltraScale-MPSoC-Authentication-Certificates)

