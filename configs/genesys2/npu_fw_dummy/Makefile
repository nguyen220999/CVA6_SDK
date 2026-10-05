# SPDX-License-Identifier: GPL-2.0+

SDK_ROOT := $(abspath $(CURDIR)/../../..)

CROSS_COMPILE ?= $(SDK_ROOT)/buildroot/output/host/bin/riscv64-buildroot-linux-gnu-
CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
MKIMAGE ?= $(SDK_ROOT)/buildroot/output/host/bin/mkimage

# Override these two variables if the NPU control core uses another ISA/ABI.
RISCV_ARCH ?= rv64im
RISCV_ABI  ?= lp64

BUILD_DIR := build/npu_fw
SOURCE    := npu_fw_test.c
LINKER    := npu_fw.ld
OBJECT    := $(BUILD_DIR)/npu_fw_test.o
ELF       := $(BUILD_DIR)/npu_fw.elf
MAP       := $(BUILD_DIR)/npu_fw.map
LIST      := $(BUILD_DIR)/npu_fw.lst
BIN       := npu_fw.bin
FIT       := NPU_fw.itb
ITS       := viettel_npu.its

CPPFLAGS :=
CFLAGS   := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
	-Os -g -Wall -Wextra \
	-ffreestanding -fno-builtin -fno-common \
	-fno-pic -fno-pie -fno-stack-protector \
	-fno-unwind-tables -fno-asynchronous-unwind-tables \
	-ffunction-sections -fdata-sections -msmall-data-limit=0 \
	-MMD -MP
LDFLAGS  := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
	-nostdlib -nostartfiles -static -no-pie \
	-Wl,-T,$(LINKER) -Wl,-Map,$(MAP) \
	-Wl,--gc-sections -Wl,--build-id=none

.PHONY: all fit disasm clean

all: $(BIN)

fit: $(FIT)

disasm: $(LIST)

$(BUILD_DIR):
	mkdir -p $@

$(OBJECT): $(SOURCE) | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(ELF): $(OBJECT) $(LINKER)
	$(CC) $(LDFLAGS) $(OBJECT) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(LIST): $(ELF)
	$(OBJDUMP) -d -S $< > $@

$(FIT): $(BIN) $(ITS)
	$(MKIMAGE) -f $(ITS) $@

clean:
	$(RM) $(BIN) $(FIT)
	$(RM) -r $(BUILD_DIR)

-include $(OBJECT:.o=.d)
