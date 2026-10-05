/* SPDX-License-Identifier: MIT */
/*
 * Minimal RV64 startup for the CVA6 FSBL port.
 *
 * The original file was copied from U-Boot and entered board_init_f(). That
 * is not the C entry point of the ZynqMP FSBL sources. xfsbl_main.c defines
 * int main(void), so this startup performs only the architecture work needed
 * before calling main().
 */

    .section .text.startup, "ax", @progbits
    .align  2
    .globl  _start
    .type   _start, @function

_start:
    /* Only CONFIG_SPL_RISCV_BOOT_HART_ID=0 runs the FSBL. */
    csrr    a0, mhartid
    mv      tp, a0
    bnez    a0, .Lsecondary_hart

    /* Do not accept interrupts before the CVA6 interrupt HAL is ready. */
    csrw    mie, zero
    csrci   mstatus, 0x8

    /* lp64d code may execute F/D instructions; enable the M-mode FS state. */
    li      t0, 0x6000
    csrs    mstatus, t0

    /* Park synchronous traps instead of using an uninitialized trap table. */
    la      t0, .Ltrap
    csrw    mtvec, t0

    /*
     * RISC-V linker relaxation can turn "la gp" into "mv gp, gp". Disable
     * relaxation around this sequence because gp has no valid reset value.
     */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* CONFIG_SPL_STACK=0x08060000, exported by lscript_cva6.ld. */
    la      sp, __stack_top
    andi    sp, sp, -16

    /* Clear the complete NOLOAD area before entering C. */
    la      t0, __bss_start
    la      t1, __bss_end
.Lclear_bss:
    bgeu    t0, t1, .Lcall_main
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .Lclear_bss

.Lcall_main:
    /* First C entry point: int main(void) in src/xfsbl_main.c. */
    call    main

    /* main() is not expected to return after handoff or error lockdown. */
.Lmain_returned:
    wfi
    j       .Lmain_returned

    .align  2                       /* mtvec BASE must be 4-byte aligned. */
.Ltrap:
    wfi
    j       .Ltrap

.Lsecondary_hart:
    /* Secondary harts remain parked until a later CVA6 SMP port wakes them. */
    csrw    mie, zero
    csrci   mstatus, 0x8
.Lsecondary_wait:
    wfi
    j       .Lsecondary_wait

    .size   _start, . - _start

    /*
     * void XFsbl_Exit(uintptr_t handoff_address, uint32_t flags)
     *
     * a0: next-stage entry address
     * a1: 1 performs an RV64 handoff; 0 or the ARM 32-bit flag parks the hart.
     *
     * The original implementation in src/xfsbl_exit.S changes ARM execution
     * state, MMU and cache controls.  Those operations have no direct RISC-V
     * equivalent.  The CVA6 port keeps interrupts disabled, orders outstanding
     * memory accesses, synchronizes the instruction stream and jumps directly
     * to the next-stage entry point.
     */
    .align  2
    .globl  XFsbl_Exit
    .type   XFsbl_Exit, @function
XFsbl_Exit:
    li      t1, 1
    bne     a1, t1, .Lfsbl_exit_park

    mv      t0, a0
    csrw    mie, zero
    csrci   mstatus, 0x8
    fence   iorw, iorw
    fence.i
    jr      t0

.Lfsbl_exit_park:
    csrw    mie, zero
    csrci   mstatus, 0x8
.Lfsbl_exit_wait:
    wfi
    j       .Lfsbl_exit_wait

    .size   XFsbl_Exit, . - XFsbl_Exit

    .section .note.GNU-stack, "", @progbits
