// SPDX-License-Identifier: MIT

/* Temporary Xilinx cache-API compatibility for the CVA6 port. */

#include "xil_cache.h"

static inline void Cva6DataFence(void)
{
	__asm__ volatile ("fence iorw, iorw" ::: "memory");
}

void Xil_DCacheEnable(void)
{
	/* Cache enable/disable is not exposed by the current CVA6 platform HAL. */
	Cva6DataFence();
}

void Xil_DCacheDisable(void)
{
	Cva6DataFence();
}

void Xil_DCacheInvalidate(void)
{
	Cva6DataFence();
}

void Xil_DCacheInvalidateRange(INTPTR Address, INTPTR Length)
{
	(void)Address;
	(void)Length;
	Cva6DataFence();
}

void Xil_DCacheInvalidateLine(INTPTR Address)
{
	(void)Address;
	Cva6DataFence();
}

void Xil_DCacheFlush(void)
{
	/*
	 * This orders prior stores but does not clean cache lines.  It matches the
	 * current board's U-Boot fallback, whose flush_dcache_all() is a no-op.
	 */
	Cva6DataFence();
}

void Xil_DCacheFlushLine(INTPTR Address)
{
	(void)Address;
	Cva6DataFence();
}

void Xil_ICacheEnable(void)
{
	__asm__ volatile ("fence.i" ::: "memory");
}

void Xil_ICacheDisable(void)
{
	__asm__ volatile ("fence.i" ::: "memory");
}

void Xil_ICacheInvalidate(void)
{
	__asm__ volatile ("fence.i" ::: "memory");
}

void Xil_ICacheInvalidateRange(INTPTR Address, INTPTR Length)
{
	(void)Address;
	(void)Length;
	__asm__ volatile ("fence.i" ::: "memory");
}

void Xil_ICacheInvalidateLine(INTPTR Address)
{
	(void)Address;
	__asm__ volatile ("fence.i" ::: "memory");
}

void Xil_ConfigureL1Prefetch(u8 Number)
{
	(void)Number;
}
