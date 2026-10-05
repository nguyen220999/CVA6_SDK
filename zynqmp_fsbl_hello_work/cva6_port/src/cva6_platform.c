// SPDX-License-Identifier: MIT

/* Temporary platform compatibility for the incremental CVA6 FSBL port. */

#include "xil_types.h"
#include "xplatform_info.h"

/*
 * CVA6 has no ZynqMP PS silicon revision.  Return a value beyond ZynqMP v2
 * so callers do not enable the v1/v2-only PMU and RPLL workarounds.
 */
u32 XGetPSVersion_Info(void)
{
	return (u32)XPS_VERSION_2 + 1U;
}

/*
 * The original FSBL uses this ZynqMP-only API both for identification and to
 * decide whether ZynqMP PMU/PCAP hardware sequences may be executed.  CVA6 is
 * not represented by the Xilinx platform enum.  Classify it as the existing
 * non-silicon/QEMU case for now, which suppresses PMU power and isolation
 * requests.  Replace the remaining callers with CVA6-specific feature checks
 * as those subsystems are ported.
 */
u32 XGet_Zynq_UltraMp_Platform_info(void)
{
	return (u32)XPLAT_ZYNQ_ULTRA_MPQEMU;
}
