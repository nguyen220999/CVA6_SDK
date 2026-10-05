/* SPDX-License-Identifier: GPL-2.0+ */

OUTPUT_ARCH(riscv)
ENTRY(main)

MEMORY
{
	NPU_FW (rwx) : ORIGIN = 0x84000000, LENGTH = 1M
}

SECTIONS
{
	. = ORIGIN(NPU_FW);

	.text : ALIGN(4)
	{
		__image_start = .;

		/* The raw binary starts here, so main is the reset entry. */
		KEEP(*(.text.entry))
		*(.text.startup .text.startup.*)
		*(.text .text.*)
	} > NPU_FW

	.rodata : ALIGN(8)
	{
		*(.srodata .srodata.*)
		*(.rodata .rodata.*)
	} > NPU_FW

	.data : ALIGN(8)
	{
		*(.sdata .sdata.*)
		*(.data .data.*)
	} > NPU_FW

	.bss (NOLOAD) : ALIGN(8)
	{
		__bss_start = .;
		*(.sbss .sbss.*)
		*(.bss .bss.*)
		*(COMMON)
		__bss_end = .;
	} > NPU_FW

	. = ALIGN(16);
	__image_end = .;

	/DISCARD/ :
	{
		*(.comment)
		*(.note .note.*)
		*(.eh_frame .eh_frame.*)
	}

	ASSERT(__image_end <= ORIGIN(NPU_FW) + LENGTH(NPU_FW),
	       "NPU firmware exceeds its 8 MiB memory region")
}
