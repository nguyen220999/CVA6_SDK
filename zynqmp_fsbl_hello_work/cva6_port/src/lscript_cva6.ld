/* SPDX-License-Identifier: MIT */
/*
 * CVA6 FSBL linker script.
 *
 * The addresses below mirror the active U-Boot SPL configuration in
 * buildroot/output/build/uboot-custom/.config:
 *
 *   CONFIG_SPL_TEXT_BASE       = 0x08000000
 *   CONFIG_SPL_MAX_SIZE        = 0x00040000
 *   CONFIG_SPL_BSS_START_ADDR  = 0x08040000
 *   CONFIG_SPL_BSS_MAX_SIZE    = 0x00010000
 *   CONFIG_SPL_STACK           = 0x08060000
 *   CONFIG_SPL_CUSTOM_SYS_MALLOC_ADDR = 0x80500000
 *   CONFIG_SPL_SYS_MALLOC_SIZE = 0x00800000
 *
 * Code, read-only data and initialized data are part of the load image in
 * SPL_IMAGE.  Zero-initialized data and the old FSBL working buffers live in
 * the separate SPL_BSS region, matching CONFIG_SPL_SEPARATE_BSS=y.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

__spl_text_base   = 0x08000000;
__spl_max_size    = 0x00040000;
__spl_bss_base    = 0x08040000;
__spl_bss_size    = 0x00010000;
__spl_stack_top   = 0x08060000;
__spl_malloc_base = 0x80500000;
__spl_malloc_size = 0x00800000;

MEMORY
{
    SPL_IMAGE (rwx) : ORIGIN = 0x08000000, LENGTH = 0x00040000
    SPL_BSS   (rw)  : ORIGIN = 0x08040000, LENGTH = 0x00010000
}

SECTIONS
{
    . = ORIGIN(SPL_IMAGE);
    __image_copy_start = .;

    /* The reset entry must be the first instruction in the image. */
    .text : ALIGN(4)
    {
        KEEP(*start.o(.text.startup .text.startup.* .text))
        *(.text .text.*)
        *(.gnu.linkonce.t.*)
    } > SPL_IMAGE

    .rodata : ALIGN(8)
    {
        __rodata_start = .;
        *(SORT_BY_ALIGNMENT(SORT_BY_NAME(.rodata*)))
        *(.srodata .srodata.*)
        *(.gnu.linkonce.r.*)
        __rodata_end = .;
    } > SPL_IMAGE

    .init_array : ALIGN(8)
    {
        __init_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        __init_array_end = .;
    } > SPL_IMAGE

    .fini_array : ALIGN(8)
    {
        __fini_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        __fini_array_end = .;
    } > SPL_IMAGE

    .data : ALIGN(8)
    {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.gnu.linkonce.d.*)
        *(.gnu.linkonce.s.*)
        *(.got .got.*)
        __global_pointer$ = . + 0x800;
        __data_end = .;
    } > SPL_IMAGE

    .drvcfg_sec : ALIGN(8)
    {
        __drvcfgsecdata_start = .;
        KEEP(*(.drvcfg_sec))
        __drvcfgsecdata_end = .;
        __drvcfgsecdata_size = __drvcfgsecdata_end - __drvcfgsecdata_start;
    } > SPL_IMAGE

    . = ALIGN(8);
    __image_copy_end = .;
    _image_binary_end = .;

    /*
     * BSS is not stored in the binary.  The CVA6 SPL startup code clears the
     * complete range [__bss_start, __bss_end).
     */
    .bss (NOLOAD) : ALIGN(64)
    {
        __bss_start = .;
        __bss_start__ = .;

        __sbss_start = .;
        *(.sbss .sbss.*)
        *(.gnu.linkonce.sb.*)
        __sbss_end = .;

        *(.bss .bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)

        /* Fixed-name buffers inherited from the ZynqMP FSBL script. */
        . = ALIGN(64);
        KEEP(*(.handoff_params))
        . = ALIGN(64);
        KEEP(*(.bitstream_buffer))

        /* XFsbl_SaveData()/XFsbl_RestoreData() need one data-sized copy. */
        . = ALIGN(64);
        __dup_data_start = .;
        . += SIZEOF(.data);
        __dup_data_end = .;

        . = ALIGN(64);
        __bss_end = .;
        __bss_end__ = .;
    } > SPL_BSS

    _end = __bss_end;

    /* Stack grows down from CONFIG_SPL_STACK into the unused 64-KiB gap. */
    __stack_top = __spl_stack_top;
    __stack_bottom = ORIGIN(SPL_BSS) + LENGTH(SPL_BSS);
    __stack_size = __stack_top - __stack_bottom;

    /* U-Boot initializes this external malloc arena at runtime. */
    __malloc_start = __spl_malloc_base;
    __malloc_end = __spl_malloc_base + __spl_malloc_size;

    /DISCARD/ :
    {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
        *(.eh_frame_hdr)
    }

    .riscv.attributes 0 :
    {
        *(.riscv.attributes)
    }
}

ASSERT(ADDR(.text) == __spl_text_base,
       "CVA6 FSBL entry is not at CONFIG_SPL_TEXT_BASE")
ASSERT(__image_copy_end <= ORIGIN(SPL_IMAGE) + LENGTH(SPL_IMAGE),
       "CVA6 FSBL load image exceeds CONFIG_SPL_MAX_SIZE")
ASSERT(__bss_end <= ORIGIN(SPL_BSS) + LENGTH(SPL_BSS),
       "CVA6 FSBL BSS exceeds CONFIG_SPL_BSS_MAX_SIZE")
ASSERT(__stack_bottom < __stack_top,
       "CVA6 FSBL stack range is invalid")
