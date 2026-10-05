# Tóm tắt RoT Specification v0.1

## 1. Thông tin tài liệu

| Hạng mục | Nội dung |
|---|---|
| Tài liệu nguồn | `RoT_Specification_v0.1.docx` |
| Trạng thái | Design baseline |
| Revision trong tài liệu | `0.1s` |
| Thời điểm | August 2026 |
| Phạm vi | Kiến trúc RoT, ranh giới với application SoC và giao diện RoT–BMU |
| Đối tượng | SoC architect, RTL/firmware engineer và security evaluator |

Tài liệu định nghĩa một Root of Trust (RoT) cách ly, always-on cho SoC RISC-V. RoT chạy trên một Ibex RV32 nhỏ và là thành phần đầu tiên đưa ra quyết định bảo mật, chịu trách nhiệm secure boot, dịch vụ mật mã, device identity, attestation, lifecycle, chống rollback và quyền cho phép application cores khởi động.

Không phần mềm nào được chạy trước RoT. Một hardwired power-on sequencer không có core và không có instruction fetch chỉ làm nhiệm vụ cấp nguồn RoT, chờ power-good rồi nhả reset.

## 2. Ba invariant nền tảng

### INV-1 — Asymmetric isolation

Application subsystem không có đường truy cập vào:

- RoT ROM và RoT SRAM.
- OTP và lifecycle controller.
- Key manager hoặc các thanh ghi chứa secret.

Application chỉ gửi request qua mailbox và các register window được RACL kiểm soát.

RoT được phép đọc/ghi application memory để xác thực và đặt firmware, nhưng mọi truy cập phải đi qua:

```text
SoC Proxy → BAT address translation → AC Range Check
```

Mọi access không khớp một range được cấp phép phải bị chặn và ghi nhận. Đây là default-deny.

### INV-2 — Reset asymmetry

Không thành phần nào bên ngoài RoT, kể cả BMU, được phép:

- Reset RoT.
- Clock-gate hoặc power-down RoT.
- Halt hoặc single-step Ibex.

RoT chỉ có hai nguồn reset:

- Hardwired power-on sequencer.
- Alert escalation bên trong RoT.

Mọi RoT reset phải chạy lại toàn bộ boot sequence. Không có partial hoặc fast RoT restart.

### INV-3 — Release authority

Application core chỉ thoát reset khi đồng thời có:

```text
BMU sequencing complete
AND
RoT core_release_grant
```

`core_release_grant` là tín hiệu hardware multi-bit do RoT tạo và được AND trực tiếp vào reset de-assert path. BMU firmware không thể tạo grant bằng register write.

## 3. Threat model

Tài liệu giả định attacker có thể:

| ID | Khả năng của attacker |
|---|---|
| A1 | Sửa tùy ý SPI NOR/eMMC, kể cả sau khi RoT đã đọc và verify |
| A2 | Probe, record và inject traffic trên SPI, DDR, MMC |
| A3 | Chạy code tùy ý ở application M-mode, kể cả TEE bị compromise |
| A4 | Gửi giá trị và chuỗi truy cập tùy ý tới mọi register interface application-visible của RoT |
| A5 | Clock, voltage, EM hoặc laser fault injection |
| A6 | Power, EM và timing side-channel |
| A7 | Rollback về firmware cũ nhưng vẫn có chữ ký hợp lệ |
| A8 | Mở lại JTAG trên production device |
| A9 | Compromise BMU để reset, undervolt hoặc release core sai quy trình |

Ngoài phạm vi:

- Full-die decapsulation và circuit edit.
- Unlimited invasive probing.
- Supply-chain substitution của chính con chip.

Giới hạn quan trọng: U-Boot, OpenSBI và kernel trong DRAM được bảo vệ khỏi sửa image trên storage nhưng không được bảo vệ khỏi attacker thay byte trên bus DDR. Để giải quyết A2 trên DDR cần memory encryption và integrity engine với MAC tree; đây là thay đổi phần cứng lớn, không phải firmware fix.

## 4. Ranh giới và cách ly

Các block bảo vệ biên:

| Block | Vai trò |
|---|---|
| 9 mailbox + crossbar | Đường inbound duy nhất từ application; mỗi mailbox có role và vùng inbox/outbox riêng |
| RACL | Kiểm tra quyền theo role, register và hướng truy cập |
| SoC Proxy + BAT | Chuyển không gian địa chỉ RoT 32-bit sang application system address 64-bit |
| AC Range Check | Allowlist 32 entry với base/limit, quyền R/W/X và lock |

Range configuration có hai tier:

- Tier 0 do immutable ROM lập và khóa trước khi application được nhả reset.
- Tier 1 do RoT-FW mở tạm thời cho từng request rồi đóng lại.
- Hardware phải từ chối và raise alert nếu Tier 1 overlap, widen hoặc override Tier 0.

Mỗi stage chạy trên application side phải nằm trong vùng write-protect. Bộ lọc phải chặn mọi initiator, bao gồm CPU và DMA. PMP của riêng core không thay thế được firewall này.

## 5. Các block phần cứng của RoT

### 5.1 Compute và memory

- Ibex RV32IMCB hardened:
  - Dual-core lockstep.
  - ECC.
  - PMP.
  - I-cache scrambling.
  - Dummy instruction.
  - Randomized register reset.
- Mask ROM bất biến.
- `rom_ctrl` hash toàn bộ ROM trước khi nhả Ibex.
- Main SRAM có scrambling và ECC.
- Mailbox SRAM tách vật lý khỏi vùng chứa secret.

### 5.2 Crypto

| Block | Chức năng |
|---|---|
| KMAC | SHA-3, SHAKE, cSHAKE, KMAC và key derivation |
| HMAC | SHA-256/384 và HMAC |
| AES | AES-128/192/256, gồm CTR và GCM |
| OTBN | RSA, ECDSA/ECDH P-256/P-384, Ed25519 và post-quantum signatures |

OTBN cho phép algorithm agility. Image manifest chỉ định thuật toán, còn OTP quy định thuật toán nào được phép trong lifecycle hiện tại.

### 5.3 Entropy

```text
entropy_src → CSRNG → EDN0/EDN1 → consumers
```

- `entropy_src`: nguồn nhiễu vật lý và continuous health tests.
- CSRNG: CTR_DRBG dựa trên AES.
- EDN: phân phối entropy tới consumer.
- Một EDN riêng phục vụ masked AES/KMAC.

### 5.4 OTP, lifecycle và alert

OTP chứa:

- UDS không software nào đọc được.
- Device identifier.
- Digest của firmware signing authorities.
- Key revocation bits.
- Anti-rollback counters.
- Lifecycle state và expected ROM digest.

Lifecycle:

```text
RAW
→ TEST_UNLOCKED
→ TEST_LOCKED
→ DEV / PROD
→ PROD_END / RMA / SCRAP
```

Chuyển trạng thái một chiều. RMA phải xóa secret trước khi mở debug.

Alert ladder:

```text
interrupt core
→ wipe secrets
→ reset RoT
→ hold toàn SoC
```

Escalation reset phải được đếm để không biến reset thành unlimited fault-injection retry oracle.

## 6. Anti-rollback và A/B update

Rollback counter không tăng ngay khi image verify thành công.

Quy trình mặc định:

1. Update slot A.
2. Boot và health-check slot A.
3. Update slot B.
4. Boot và health-check slot B.
5. Khi cả hai slot ở security version mới, `UPDATE_CONFIRM` mới burn counter.

Fuse budget đề xuất:

| Thành phần | Số bit counter |
|---|---:|
| RoT-FW | 32 |
| BMU firmware | 16 |
| FSBL | 16 |
| SPL/U-Boot/OpenSBI/kernel | 32 dùng chung |

Dùng chung counter cho application chain yêu cầu SPL, U-Boot, OpenSBI và kernel được version, sign và release theo một bộ. Nếu muốn update độc lập phải chia fuse budget trước khi fuse map bị đóng băng.

## 7. Boot media và software stages

### 7.1 Boot media

| Loại | Nội dung | Yêu cầu |
|---|---|---|
| RoT-private medium | RoT-FW, BMU firmware, FSBL | RoT-private SPI; đọc được khi BMU bị giữ reset và application chưa cấp nguồn |
| Bulk medium | SPL, U-Boot, OpenSBI, OS | Chỉ truy cập sau khi SoC được bring-up; stage hiện tại load và RoT verify |

Hai flash riêng là phương án khuyến nghị. Nếu dùng một flash, RoT nên sở hữu write-protect pin hoặc điều khiển mux và application không được có quyền sở hữu trước core release.

### 7.2 Software stages

| Stage | Chạy trên | Nơi thực thi | Xác thực bởi |
|---|---|---|---|
| Power-on sequencer | Hardwired FSM | — | — |
| ROM digest check | Hardware | — | — |
| RoT ROM | Ibex | RoT ROM | `rom_ctrl` |
| RoT-FW | Ibex | RoT SRAM | RoT ROM |
| BMU boot ROM | BMU core | BMU ROM | Chỉ measured |
| BMU firmware | BMU core | BMU IRAM | RoT-FW |
| ZSBL/FSBL | Application core 0 | On-die SRAM | RoT-FW |
| SPL | Application core 0 | On-die SRAM | RoT gate |
| U-Boot | Application core 0 | DRAM | RoT gate |
| OpenSBI + OS | Application cores | DRAM | RoT gate |

Boot state machine:

```text
INIT
→ ROT_FW_OK
→ BMU_OK
→ FSBL_OK
→ SPL_OK
→ UBOOT_OK
→ OPENSBI_OK
→ OS_RUNNING
```

Mỗi trạng thái chỉ được advance một lần và phải đúng successor.

## 8. Secure-boot flow

```text
Hardwired sequencer
    ↓
rom_ctrl kiểm tra RoT ROM
    ↓
RoT ROM xác thực RoT-FW
    ↓
RoT-FW xác thực BMU firmware
    ↓
Ghi BMU firmware vào BMU IRAM và khóa write
    ↓
Nhả BMU để bring-up toàn SoC
    ↓
RoT xác thực FSBL và copy vào application SRAM
    ↓
RoT khóa vùng SRAM chứa FSBL
    ↓
RoT cấp core_release_grant
    ↓
FSBL/SPL/U-Boot/OpenSBI load stage tiếp theo
    ↓
RoT xác thực stage qua mailbox gate
    ↓
RoT ghi measurement và advance key manager
    ↓
Stage mới được phép thực thi
```

Ba yêu cầu quan trọng:

- RoT lock vùng đích trước khi hash.
- Key manager chỉ advance khi verification thành công.
- Vùng của stage trước chỉ được unlock khi RoT quan sát stage sau đã bắt đầu chạy.

OpenSBI không được unlock vì tiếp tục resident ở M-mode. Kernel được đo và xác thực lúc load nhưng không bị RoT khóa vĩnh viễn vì kernel cần relocation, alternative/static-key patching và giải phóng init section.

## 9. Copy-then-execute

Stage chạy từ on-die SRAM phải tuân theo:

```text
fetch
→ copy vào SRAM
→ lock write
→ hash/signature verify
→ execute
```

Không được execute-in-place từ SPI/eMMC vì attacker có thể thay dữ liệu sau verification nhưng trước instruction fetch.

Với DRAM-resident stage:

- Chống sửa storage trước boot.
- Chống CPU/DMA on-die ghi vào vùng đã lock.
- Không chống DDR bus interposer.

## 10. Failure handling

Ba tầng xử lý:

1. A/B slot fallback.
2. Authenticated recovery bằng recovery key authority riêng.
3. Terminal fail-closed nếu recovery không khả dụng hoặc thất bại.

ROM chỉ hỗ trợ A/B fallback khi RoT-FW lỗi. Recovery qua mailbox chỉ khả dụng sau khi RoT-FW chạy vì trước đó chưa có requester.

Thông tin lỗi trả ra phải coarse-grained và không tiết lộ:

- Vị trí signature mismatch.
- Internal address.
- Key material.
- Timing phụ thuộc secret.

## 11. Verify image lớn hơn RoT SRAM

RoT không cần giữ toàn bộ image trong SRAM:

- Inline hashing trong DMA là phương án ưu tiên.
- Chunked streaming dùng fixed-size buffer.
- Translation window có thể trượt qua image.

Root filesystem không được hash toàn bộ mỗi lần boot. RoT verify chữ ký trên Merkle-tree root hash, bind root hash vào measurement, còn kernel verify từng block khi đọc.

## 12. DICE, key manager và attestation

Khóa được dẫn xuất từ:

```text
UDS
+ hardware state
+ lifecycle
+ ROM measurement
+ toàn bộ software measurement chain
```

CDI chỉ tồn tại trong flip-flop, không có bus address và mất hoàn toàn khi reset/power-off.

Năm operation:

- `advance_slot(src, dst)`
- `generate(slot, version, salt, dest)`
- `erase_slot(slot)`
- `advance_lock()`
- `disable()`

Khóa được sideload trực tiếp vào crypto engine, không đi qua firmware hoặc mailbox.

Ở steady state chỉ giữ:

- Runtime sealing context.
- Attestation context.

Attestation:

- DICE certificate chain, một certificate cho mỗi boot layer.
- Nonce từ verifier tối thiểu 32 byte là bắt buộc.
- Requester chỉ chọn thời điểm attest, không được chọn nội dung claims.

Sealing không tự chống rollback. State không được phép quay ngược phải gắn với monotonic counter lưu trong RoT-controlled, wear-levelled, power-loss-safe nonvolatile storage. OTP không phù hợp cho runtime counters.

## 13. Security Monitor và enclave

RoT chỉ nhận diện requester ở cấp subsystem bằng mailbox instance. RoT không quản lý từng enclave; Security Monitor ở M-mode quản lý enclave identity và lifecycle.

Giới hạn được tuyên bố:

> Sealing cách ly thiết bị và software state, đồng thời cách ly enclave trước S-mode/U-mode attacker, nhưng không bảo vệ trước M-mode attacker hoặc Security Monitor bị compromise.

Baseline dùng opaque handle:

- RoT không trả raw sealing key.
- Handle gồm salt và MAC bằng per-boot key.
- RoT chỉ seal key nhỏ; bulk encryption thực hiện bên ngoài.

Hardware usage tag tách miền khóa:

| Usage | Key class |
|---:|---|
| `0x01` | Boot-stage keys |
| `0x02` | Attestation keys |
| `0x03` | Enclave sealing keys |
| `0x04` | Monotonic counters |
| `0x05` | Handle authentication |

## 14. Mailbox

Có chín mailbox độc lập. Inbox/outbox SRAM nằm bên trong RoT và không có application address.

Message envelope:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 2 | `protocol_version` |
| 2 | 2 | `command_id` |
| 4 | 4 | `payload_length` |
| 8 | 4 | `sequence_number` |
| 12 | … | `payload` |

Quy tắc:

- Hardware khóa inbox sau submit.
- Firmware đọc mỗi field đúng một lần rồi copy vào private SRAM.
- `payload_length` phải bằng số byte thực tế đã ghi.
- Boot và Policy dùng fixed binary layout.
- CBOR chỉ dùng cho management và attestation.
- Boot mailbox riêng không thể bị requester khác làm nghẽn.
- Có rate limit và per-request timeout.

Nhóm command:

```text
Boot:    VERIFY_IMAGE, GET_BOOT_STATE,
         REPORT_STAGE_COMPLETE, CORE_RELEASE_REQUEST

Crypto:  HASH, HMAC, AES_ENC, AES_DEC, RANDOM

Key:     SEAL, UNSEAL, DERIVE_KEY, GET_PUBLIC_KEY

Attest:  GET_EVIDENCE, GET_CERT_CHAIN, GET_MEASUREMENTS

Policy:  GET_LIFECYCLE_STATE, GET_VERSION,
         GET_ROLLBACK_COUNTERS

Update:  UPDATE_BEGIN, UPDATE_WRITE, UPDATE_FINALIZE,
         UPDATE_ACTIVATE, UPDATE_CONFIRM
```

## 15. RoT firmware

Hai lớp chạy trên Ibex:

- Immutable ROM chỉ làm bring-up tối thiểu, boundary lock, OTP/lifecycle read, key-manager advance đầu tiên và verify RoT-FW.
- Mutable RoT-FW chứa parser, image verification, update, recovery, attestation và application services.

Coding rules:

- Fail closed.
- Không có unbounded loop.
- Kiểm tra mọi length/address trước khi dùng.
- Single-fetch đối với mailbox.
- Firmware text được ROM khóa bằng PMP.
- Redundant checks cho quyết định security-critical.
- Constant-time compare.
- Explicit zeroization.
- Không dynamic allocation.
- Production build compile-out mọi bypass/allow-unsigned path.

## 16. Image manifest

Mỗi mutable stage dùng manifest:

| Trường | Mục đích |
|---|---|
| `magic`, `format_version` | Nhận diện format |
| `image_length` | Kích thước image |
| `security_version` | Chống rollback |
| `key_slot` | Signing authority |
| `signature_algorithm` | Thuật toán chữ ký |
| `digest_algorithm` | Thuật toán hash |
| `load_address` | Địa chỉ nạp |
| `entry_address` | Entry point |
| `platform_id` | Bind image với platform |
| `flags` | Policy bổ sung |
| `digest` | Hash của image body |
| `signature` | Chữ ký trên manifest và digest |

Thứ tự verification:

```text
format
→ length
→ rollback
→ key revocation
→ algorithm policy
→ digest
→ signature
→ address range
→ measurement/key-manager advance
→ decrypt nếu cần
→ copy
→ execute
```

Với encrypted update, phải verify ciphertext trước khi decrypt hoặc dùng authenticated encryption và không phát plaintext trước khi tag hợp lệ.

CRC32 chỉ phát hiện lỗi ngẫu nhiên, không có vai trò trong security chain.

## 17. RoT–BMU contract

BMU giữ cơ chế power/reset/clock cho toàn SoC; RoT giữ quyền quyết định application core có được chạy hay không.

Quy tắc:

- Không secret/CDI nào đi qua interface RoT–BMU.
- Mọi tín hiệu BMU→RoT là untrusted input.
- RoT quan sát reset state và so sánh với grant đã cấp.
- BMU mất heartbeat chỉ được giữ application subsystem, không được reset RoT.
- Warm reset core phải xóa grant và yêu cầu verification/grant epoch mới.
- Resume không được phép bỏ qua verification.
- RoT reset luôn chạy lại từ đầu.

Ưu tiên dùng fixed regulator hoặc regulator có power-on default đúng, cùng on-die always-on oscillator. Voltage/clock monitors phải hoạt động trước lần verification đầu tiên.

## 18. Implementation phasing

| Phase | Kết quả phải đạt |
|---|---|
| 1 | Verified boot có trust anchor thực: ROM, crypto, OTP, lifecycle, anti-rollback, debug lock, private SPI, core grant và SRAM write-protect |
| 2 | Mutable RoT-FW, signed update, A/B, recovery, BMU verification và hoàn thiện reset asymmetry |
| 3 | Mailbox, RACL, SoC Proxy/BAT, Tier-0/Tier-1 range check và rate limiting |
| 4 | DICE key manager, identity, attestation, sealing, monotonic counters và enclave handles |
| Song song | Provisioning, UDS, manufacturing CA, token custody và lifecycle flow |

Tài liệu nhấn mạnh: verify chữ ký nhưng JTAG còn mở, không có lifecycle hoặc không chống rollback thì chưa thể tuyên bố secure boot.

## 19. Rủi ro chính

- Key manager/DPE chưa trưởng thành bằng classic single-chain key manager.
- Boot latency khi hash/verify image nhiều MB trên core 32-bit.
- Masked crypto có thể bị thiếu entropy.
- Range-check IP có thể không hỗ trợ outbound filtering.
- Tier-0/Tier-1 overlap check có thể cần custom RTL.
- Chỉ có 32 range entry cho nhiều mục đích.
- Pre-RoT sequencer và BMU ROM có nguy cơ scope creep.
- Off-die regulator tạo fault-injection surface.
- Sai tích hợp reset, clock, grant hoặc range lock có thể phá toàn bộ invariant.
- DDR bus integrity chưa được xử lý.
- Enclave isolation phụ thuộc Security Monitor.

## 20. Verification và certification

Các artefact bắt buộc:

- Threat model và traceability.
- TCB enumeration.
- Security target.
- Key management policy.
- Formal verification cho lifecycle, key manager, escalation và range locks.
- Side-channel/fault-injection test.
- Continuous mailbox fuzzing.
- Crypto power-on self-tests.
- Zeroization evidence.
- Independent penetration test.

Certification target:

- FIPS 140-3.
- NIST SP 800-193.
- TCG DICE/DPE.
- IETF RATS.
- PSA Certified/SESIP.
- Common Criteria.
- ISO/SAE 21434 và ISO 26262 nếu dùng automotive.
- EU Cyber Resilience Act.
- CNSA 2.0 cho long-life firmware signing.

Negative tests phải chứng minh rằng unsigned, wrong-key, revoked-key, rollback, truncated, oversized và overlapping image đều bị từ chối; isolation/range locks không thể bị bypass; core không thể thoát reset khi thiếu grant; key không thể xuất sai role; và production JTAG luôn bị khóa.

## 21. Liên hệ với `u-boot.itb` hiện tại

Đặc tả không nhắc đến FIT/ITB và không bắt buộc dùng native U-Boot FIT signature. Nó mô tả một generic signed image manifest.

Trạng thái project hiện tại:

- `u-boot.itb` chứa OpenSBI, U-Boot và board DTB.
- FIT chưa có node `hash` hoặc `signature`.
- SPL đang load FIT nhưng chưa xác thực chữ ký.
- Theo đặc tả, SPL, U-Boot và OpenSBI phải đi qua RoT verification gate trước khi chạy.

Hai hướng tích hợp:

1. Tạo một RoT manifest bên ngoài và ký toàn bộ file `u-boot.itb`.
2. Mở rộng RoT để hiểu signed FIT và xác thực signed configuration cùng từng payload.

Cần chốt các quyết định:

- Một `u-boot.itb` là một stage hay U-Boot/OpenSBI là hai stage riêng?
- `security_version`, `key_slot`, `platform_id` nằm trong manifest ngoài hay FIT property?
- Measurement advance một lần cho toàn ITB hay riêng từng payload?
- SPL tự verify FIT là defense-in-depth hay RoT trực tiếp verify vùng DRAM qua mailbox?

Theo đúng đặc tả, RoT phải là verification gate. Chỉ bật `CONFIG_SPL_FIT_SIGNATURE` trong SPL chưa đủ nếu SPL có thể chạy stage tiếp theo mà không qua RoT mailbox, measurement advance và stage gate.
