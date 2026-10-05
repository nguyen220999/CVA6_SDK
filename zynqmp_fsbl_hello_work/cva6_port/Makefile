# SPDX-License-Identifier: MIT

# Build the ported FSBL sources and link a freestanding RV64 executable.

# The log target uses bash pipefail so a compiler/linker error is not hidden
# by tee returning success.
SHELL := /bin/bash

PORT_DIR := $(abspath $(CURDIR))
FSBL_DIR := $(abspath $(PORT_DIR)/..)
SDK_ROOT := $(abspath $(FSBL_DIR)/..)
SRC_DIR  := $(PORT_DIR)/src
LDSCRIPT ?= $(SRC_DIR)/lscript_cva6.ld

# Use the complete Buildroot host toolchain.  Do not default to
# $(PORT_DIR)/compiler: the copied gcc symlink there needs toolchain-wrapper
# and the associated sysroot, so copying only compiler executables is not
# sufficient.
CROSS_COMPILE ?= $(SDK_ROOT)/buildroot/output/host/bin/riscv64-buildroot-linux-gnu-
CC := $(CROSS_COMPILE)gcc
AR := $(CROSS_COMPILE)ar
OBJCOPY := $(CROSS_COMPILE)objcopy
SIZE := $(CROSS_COMPILE)size

# Temporary dependency on the old BSP headers.  Drivers and hardware constants
# from this directory must eventually be replaced by the CVA6 HAL.
XILINX_BSP_INCLUDE ?= $(abspath $(CURDIR)/include)

RISCV_ARCH ?= rv64imafdc_zicsr_zifencei
RISCV_ABI  ?= lp64d
RISCV_CMODEL ?= medlow
# RISC-V timer frequency from the CVA6 platform device tree. The bare-metal
# usleep/msleep/sleep implementation uses this value when reading CSR time.
CVA6_TIMEBASE_HZ ?= 100000
CVA6_UART_BASE ?= 0x10020000
CVA6_UART_INPUT_HZ ?= 100000000
CVA6_UART_BAUD ?= 115200

BUILD_DIR := $(PORT_DIR)/build-cva6-c-only
BUILD_LOG ?= $(PORT_DIR)/build.log
SOURCES := $(sort $(wildcard $(SRC_DIR)/*.c))

# The original xfsbl_rsa_sha.c drives the ZynqMP CSU SHA3 engine through
# libxilsecure. CVA6 has no port of that implementation yet, so keep checksum
# support disabled instead of linking a non-functional security stub.
CVA6_SHA3 ?= 0
ifeq ($(CVA6_SHA3),0)
SOURCES := $(filter-out $(SRC_DIR)/xfsbl_rsa_sha.c,$(SOURCES))
endif

# xfsbl_qspi.c is for the ZynqMP XQspiPsu controller at 0xff0f0000. The CVA6
# device tree instead exposes a SiFive SPI controller at 0x10030000.
CVA6_QSPI ?= 0
ifeq ($(CVA6_QSPI),0)
SOURCES := $(filter-out $(SRC_DIR)/xfsbl_qspi.c,$(SOURCES))
endif

# CSU DMA, PCAP and the associated bitstream path are ZynqMP hardware blocks.
# Keep them out until an equivalent CVA6 data path is deliberately ported.
CVA6_CSU_DMA ?= 0
ifeq ($(CVA6_CSU_DMA),0)
SOURCES := $(filter-out $(SRC_DIR)/xfsbl_csu_dma.c,$(SOURCES))
endif

OBJECTS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SOURCES))
DEPS := $(OBJECTS:.o=.d)
ARCHIVE := $(BUILD_DIR)/libxfsbl-cva6-port.a
START_SOURCE := $(PORT_DIR)/start.S
START_OBJECT := $(BUILD_DIR)/start.o
ELF := $(BUILD_DIR)/fsbl_cva6.elf
BIN := $(BUILD_DIR)/fsbl_cva6.bin
MAP := $(BUILD_DIR)/fsbl_cva6.map

# Add port-specific startup/HAL objects and RISC-V BSP archives without
# editing this Makefile, for example:
#   make EXTRA_OBJS="src/cva6_trap.o" CVA6_BSP_LIBS="/path/libcva6_bsp.a"
EXTRA_OBJS ?=
CVA6_BSP_LIBS ?=

CPPFLAGS := \
	-I$(SRC_DIR) \
	-I$(XILINX_BSP_INCLUDE) \
	-I$(PORT_DIR)/include \
	-include cva6_port_compat.h \
	-DSDT \
	-DCVA6_PORT \
	-DCVA6_TIMEBASE_HZ=$(CVA6_TIMEBASE_HZ) \
	-DCVA6_UART_BASE=$(CVA6_UART_BASE) \
	-DCVA6_UART_INPUT_HZ=$(CVA6_UART_INPUT_HZ) \
	-DCVA6_UART_BAUD=$(CVA6_UART_BAUD)

ifeq ($(CVA6_SHA3),0)
CPPFLAGS += -DCVA6_PORT_NO_SHA3
endif

ifeq ($(CVA6_QSPI),0)
CPPFLAGS += -DFSBL_QSPI_EXCLUDE
endif

ifeq ($(CVA6_CSU_DMA),0)
CPPFLAGS += -DCVA6_PORT_NO_CSU_DMA -DFSBL_BS_EXCLUDE
endif

CFLAGS := \
	-march=$(RISCV_ARCH) \
	-mabi=$(RISCV_ABI) \
	-mcmodel=$(RISCV_CMODEL) \
	-std=gnu11 \
	-Os -g3 \
	-ffreestanding -fno-builtin -fno-common \
	-fno-pic -fno-pie -fno-stack-protector \
	-fno-unwind-tables -fno-asynchronous-unwind-tables \
	-ffunction-sections -fdata-sections -msmall-data-limit=0 \
	-MMD -MP \
	-w

LDFLAGS := \
	-march=$(RISCV_ARCH) \
	-mabi=$(RISCV_ABI) \
	-mcmodel=$(RISCV_CMODEL) \
	-nostartfiles -nostdlib -static -no-pie \
	-Wl,--build-id=none \
	-Wl,--gc-sections \
	-Wl,--no-dynamic-linker \
	-Wl,-Map,$(MAP) \
	-Wl,-T,$(LDSCRIPT)

# libgcc supplies compiler-generated RV64 arithmetic helpers. Do not link the
# Buildroot Linux libc into this bare-metal image; memcpy/memset and platform
# services must come from the CVA6 HAL/BSP.
LDLIBS ?= -lgcc

# start.S is now a freestanding CVA6 entry and has no U-Boot header dependency.
ASM_CPPFLAGS := -D__ASSEMBLY__

ASFLAGS := \
	-march=$(RISCV_ARCH) \
	-mabi=$(RISCV_ABI) \
	-mcmodel=$(RISCV_CMODEL) \
	-g3 \
	-fno-pic -fno-pie -ffixed-x3 -fno-common \
	-ffunction-sections -fdata-sections \
	-MMD -MP

ASM_DEPS := $(START_OBJECT:.o=.d)

.PHONY: all objects elf log check help clean

all: log

objects: check $(START_OBJECT) $(ARCHIVE)

elf: $(ELF) $(BIN)

# Show the complete build output on the terminal and save the same output.
# PIPESTATUS preserves the recursive make result instead of tee's result.
log:
	@mkdir -p "$(dir $(BUILD_LOG))"
	@echo "CVA6 FSBL build log: $(BUILD_LOG)"
	@$(MAKE) --no-print-directory elf 2>&1 | tee "$(BUILD_LOG)"; \
		exit $${PIPESTATUS[0]}

check:
	@test -x "$(CC)" || { echo "ERROR: CVA6 compiler not found: $(CC)"; exit 1; }
	@test -x "$(OBJCOPY)" || { echo "ERROR: CVA6 objcopy not found: $(OBJCOPY)"; exit 1; }
	@test -x "$(SIZE)" || { echo "ERROR: CVA6 size tool not found: $(SIZE)"; exit 1; }
	@test -f "$(XILINX_BSP_INCLUDE)/xil_types.h" || { echo "ERROR: temporary Xilinx BSP headers not found: $(XILINX_BSP_INCLUDE)"; exit 1; }
	@test -f "$(LDSCRIPT)" || { echo "ERROR: CVA6 linker script not found: $(LDSCRIPT)"; exit 1; }

$(OBJECTS) $(START_OBJECT): Makefile | check

$(ARCHIVE): $(OBJECTS) Makefile
	$(RM) $@
	$(AR) rcs $@ $(OBJECTS)
	@echo
	@echo "CVA6 FSBL archive: $@"

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(START_OBJECT): $(START_SOURCE)
	@mkdir -p $(dir $@)
	$(CC) $(ASM_CPPFLAGS) $(ASFLAGS) -c $< -o $@
	@echo "CVA6 startup object: $@"

$(ELF): $(START_OBJECT) $(ARCHIVE) $(LDSCRIPT) $(EXTRA_OBJS) Makefile | check
	$(CC) $(LDFLAGS) -o $@ \
		$(START_OBJECT) $(EXTRA_OBJS) \
		-Wl,--start-group \
		-Wl,--whole-archive $(ARCHIVE) -Wl,--no-whole-archive \
		$(CVA6_BSP_LIBS) $(LDLIBS) \
		-Wl,--end-group
	$(SIZE) $@
	@echo "CVA6 FSBL ELF: $@"
	@echo "CVA6 FSBL map: $(MAP)"

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "CVA6 FSBL binary: $@"

help:
	@echo "CVA6 FSBL port build"
	@echo "  make            Build ELF/BIN and save output to $(BUILD_LOG)"
	@echo "  make elf        Build fsbl_cva6.elf and fsbl_cva6.bin"
	@echo "  make objects    Build only the FSBL archive and CVA6 start.o"
	@echo "  make log        Build and save compiler/linker output to $(BUILD_LOG)"
	@echo "  make clean      Remove $(BUILD_DIR) and $(BUILD_LOG)"
	@echo "  make V=1        Commands are already printed by make"
	@echo "  linker script   $(LDSCRIPT)"
	@echo
	@echo "Overrides: CROSS_COMPILE, XILINX_BSP_INCLUDE, LDSCRIPT, RISCV_ARCH, RISCV_ABI, RISCV_CMODEL, CVA6_TIMEBASE_HZ, CVA6_UART_BASE, CVA6_UART_INPUT_HZ, CVA6_UART_BAUD, CVA6_SHA3, CVA6_QSPI, CVA6_CSU_DMA, BUILD_LOG"
	@echo "Link inputs: EXTRA_OBJS, CVA6_BSP_LIBS, LDLIBS"

clean:
	$(RM) -r $(BUILD_DIR) $(BUILD_LOG)

-include $(DEPS) $(ASM_DEPS)
