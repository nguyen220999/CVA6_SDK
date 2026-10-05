/* SPDX-License-Identifier: MIT */
#ifndef CVA6_PORT_COMPAT_H
#define CVA6_PORT_COMPAT_H

/*
 * Temporary declarations used while the original ZynqMP C sources are
 * compiled with the CVA6/RISC-V toolchain.  They do not make the resulting
 * objects runnable on CVA6.  Replace each declaration with a CVA6 HAL
 * implementation as the port progresses.
 */

#ifndef __FILENAME__
#define __FILENAME__ __FILE__
#endif

unsigned int XGetPSVersion_Info(void);
unsigned int XGet_Zynq_UltraMp_Platform_info(void);

#endif /* CVA6_PORT_COMPAT_H */
