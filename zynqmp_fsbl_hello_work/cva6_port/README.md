# CVA6 FSBL port build

This directory is the first mechanical stage of porting the ZynqMP FSBL to
CVA6. It compiles the existing C translation units with the same RISC-V ISA
and ABI currently used by the CVA6 U-Boot build:

```text
-march=rv64imafdc_zicsr_zifencei
-mabi=lp64d
-mcmodel=medlow
```

Run from the SDK root:

```sh
make -C zynqmp_fsbl_hello_work/cva6_port
```

The object-only build is still available with:

```sh
make -C zynqmp_fsbl_hello_work/cva6_port objects
```

The full link command is:

```sh
make -C zynqmp_fsbl_hello_work/cva6_port \
  EXTRA_OBJS="/path/to/cva6_startup_support.o" \
  CVA6_BSP_LIBS="/path/to/libcva6_bsp.a"
```

The ZynqMP CSU SHA3 wrapper is disabled by default because there is no CVA6
SHA3 HAL yet. A boot image requesting a SHA3 checksum is rejected rather than
accepted without verification. After providing a compatible SHA3
implementation/library, enable that path with `CVA6_SHA3=1`.

The ZynqMP `XQspiPsu` backend is also disabled by default. The current CVA6
hardware description uses a SiFive SPI controller at `0x10030000`, so the
ZynqMP driver at `0xff0f0000` must not be used. Set `CVA6_QSPI=1` only after
`xfsbl_qspi.c` has been replaced by a compatible CVA6 SPI-flash backend.

The outputs are:

```text
zynqmp_fsbl_hello_work/cva6_port/build-cva6-c-only/libxfsbl-cva6-port.a
zynqmp_fsbl_hello_work/cva6_port/build-cva6-c-only/start.o
zynqmp_fsbl_hello_work/cva6_port/build-cva6-c-only/fsbl_cva6.elf
zynqmp_fsbl_hello_work/cva6_port/build-cva6-c-only/fsbl_cva6.bin
zynqmp_fsbl_hello_work/cva6_port/build-cva6-c-only/fsbl_cva6.map
```

The archive proves that the C translation units can be consumed by the CVA6
compiler. `start.o` is linked directly so its `_start` entry cannot be skipped
by archive member selection. The linker refuses to produce the ELF until all
startup and HAL/BSP symbols are implemented. An ELF that does link is still
not automatically runnable firmware because:

- ARM translation-table and exit assembly are excluded;
- `start.S` selects hart 0, initializes `gp`/`sp`, clears BSS and calls the
  FSBL `main()` entry point;
- `src/lscript_cva6.ld` defines the CVA6 SPL memory layout, but that layout
  still needs validation against the implemented hardware;
- references to Xilinx BSP libraries remain unresolved;
- ZynqMP MMIO addresses and hardware behavior remain in the C sources;
- `XFsbl_Cva6ReadHartId()` has no implementation yet;
- the temporary A53 BSP include directory is used only to provide legacy
  types and declarations while CVA6 compatibility headers are introduced.

The next porting stage should add a CVA6 HAL and replace dependencies in this
order:

1. primitive types, MMIO access and debug output;
2. processor/hart identification and cache/barrier operations;
3. validate the CVA6 SRAM memory map and linker script on hardware;
4. startup, trap entry, stack and BSS initialization;
5. DDR and boot-device drivers;
6. FIT/image loading and OpenSBI handoff;
7. cryptographic verification and recovery behavior.

Warnings are suppressed during this mechanical stage because the temporary
ZynqMP generated headers contain duplicate hardware macros. Remove `-w` from
the Makefile as soon as those headers are replaced by native CVA6 headers.
