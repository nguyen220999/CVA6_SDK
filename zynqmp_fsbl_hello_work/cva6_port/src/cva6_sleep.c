// SPDX-License-Identifier: MIT

/* Bare-metal delay implementation for the CVA6 port. */

#include "sleep.h"

#ifndef CVA6_TIMEBASE_HZ
#define CVA6_TIMEBASE_HZ 100000UL
#endif

#if CVA6_TIMEBASE_HZ == 0
#error "CVA6_TIMEBASE_HZ must be greater than zero"
#endif

static inline u64 Cva6ReadTime(void)
{
	u64 Time;

	__asm__ volatile ("rdtime %0" : "=r" (Time));
	return Time;
}

/*
 * Convert a duration to timer ticks, rounding up so that a requested delay is
 * never shortened. Splitting quotient and remainder also avoids overflowing
 * duration * CVA6_TIMEBASE_HZ for normal long delays.
 */
static u64 Cva6DurationToTicks(u64 Duration, u64 UnitsPerSecond)
{
	u64 Ticks;
	u64 Remainder;

	Ticks = (Duration / UnitsPerSecond) * (u64)CVA6_TIMEBASE_HZ;
	Remainder = Duration % UnitsPerSecond;
	Ticks += ((Remainder * (u64)CVA6_TIMEBASE_HZ) +
		  (UnitsPerSecond - 1U)) / UnitsPerSecond;

	return Ticks;
}

static void Cva6DelayTicks(u64 Ticks)
{
	u64 Start;

	if (Ticks == 0U) {
		return;
	}

	Start = Cva6ReadTime();
	while ((Cva6ReadTime() - Start) < Ticks) {
		__asm__ volatile ("nop");
	}
}

void usleep(unsigned long Useconds)
{
	Cva6DelayTicks(Cva6DurationToTicks((u64)Useconds, 1000000U));
}

void msleep(unsigned long Mseconds)
{
	Cva6DelayTicks(Cva6DurationToTicks((u64)Mseconds, 1000U));
}

void sleep(unsigned int Seconds)
{
	Cva6DelayTicks(Cva6DurationToTicks((u64)Seconds, 1U));
}
