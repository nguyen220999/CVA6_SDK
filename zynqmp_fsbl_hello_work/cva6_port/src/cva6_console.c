// SPDX-License-Identifier: MIT

/* Minimal bare-metal xil_printf compatibility using the CVA6 SiFive UART. */

#include <stdarg.h>

#include "cva6_console.h"
#include "xil_printf.h"

#ifndef CVA6_UART_BASE
#define CVA6_UART_BASE 0x10020000UL
#endif

#ifndef CVA6_UART_INPUT_HZ
#define CVA6_UART_INPUT_HZ 100000000UL
#endif

#ifndef CVA6_UART_BAUD
#define CVA6_UART_BAUD 115200UL
#endif

#if CVA6_UART_BAUD == 0
#error "CVA6_UART_BAUD must be greater than zero"
#endif

#define CVA6_UART_TXDATA_OFFSET 0x00U
#define CVA6_UART_RXDATA_OFFSET 0x04U
#define CVA6_UART_TXCTRL_OFFSET 0x08U
#define CVA6_UART_IP_OFFSET     0x14U
#define CVA6_UART_DIV_OFFSET    0x18U

#define CVA6_UART_DATA_EMPTY_OR_FULL 0x80000000U
#define CVA6_UART_TX_ENABLE          0x00000001U
#define CVA6_UART_TXCNT_SHIFT        16U
#define CVA6_UART_TXCNT_MASK         0x00070000U
#define CVA6_UART_IP_TXWM            0x00000001U

static u32 Cva6UartInitialized;

static inline u32 Cva6UartRead(u32 Offset)
{
	return *(volatile u32 *)((UINTPTR)CVA6_UART_BASE + (UINTPTR)Offset);
}

static inline void Cva6UartWrite(u32 Offset, u32 Value)
{
	*(volatile u32 *)((UINTPTR)CVA6_UART_BASE + (UINTPTR)Offset) = Value;
}

static void Cva6UartInitialize(void)
{
	u32 Divisor;

	if (Cva6UartInitialized != 0U) {
		return;
	}

	Divisor = (u32)((((u64)CVA6_UART_INPUT_HZ + (u64)CVA6_UART_BAUD - 1U) /
			 (u64)CVA6_UART_BAUD) - 1U);
	Cva6UartWrite(CVA6_UART_DIV_OFFSET, Divisor);
	Cva6UartWrite(CVA6_UART_TXCTRL_OFFSET, CVA6_UART_TX_ENABLE);
	__asm__ volatile ("fence iorw, iorw" ::: "memory");
	Cva6UartInitialized = 1U;
}

void outbyte(char Character)
{
	Cva6UartInitialize();
	while ((Cva6UartRead(CVA6_UART_TXDATA_OFFSET) &
		CVA6_UART_DATA_EMPTY_OR_FULL) != 0U) {
		/* Wait until the transmit FIFO has room. */
	}
	Cva6UartWrite(CVA6_UART_TXDATA_OFFSET, (u32)(u8)Character);
}

void Cva6ConsoleWaitTransmitDone(void)
{
	u32 TxControl;

	Cva6UartInitialize();
	TxControl = Cva6UartRead(CVA6_UART_TXCTRL_OFFSET);

	/* TXWM is asserted when the FIFO occupancy is less than TXCNT. */
	Cva6UartWrite(CVA6_UART_TXCTRL_OFFSET,
		(TxControl & ~CVA6_UART_TXCNT_MASK) |
		(1U << CVA6_UART_TXCNT_SHIFT));
	__asm__ volatile ("fence iorw, iorw" ::: "memory");
	while ((Cva6UartRead(CVA6_UART_IP_OFFSET) & CVA6_UART_IP_TXWM) == 0U) {
		/* Wait until FIFO occupancy is zero. */
	}

	Cva6UartWrite(CVA6_UART_TXCTRL_OFFSET, TxControl);
	__asm__ volatile ("fence iorw, iorw" ::: "memory");
}

char inbyte(void)
{
	u32 Value;

	Cva6UartInitialize();
	do {
		Value = Cva6UartRead(CVA6_UART_RXDATA_OFFSET);
	} while ((Value & CVA6_UART_DATA_EMPTY_OR_FULL) != 0U);

	return (char)(Value & 0xFFU);
}

void print(const char8 *String)
{
	while (*String != '\0') {
		outbyte((char)*String);
		String++;
	}
}

static void Cva6PrintUnsigned(u64 Value, u32 Base, u32 Width, char Pad,
			      u32 UpperCase)
{
	char Buffer[32];
	u32 Count = 0U;
	u32 Digit;

	do {
		Digit = (u32)(Value % (u64)Base);
		Buffer[Count++] = (char)((Digit < 10U) ? ('0' + Digit) :
			((UpperCase != 0U ? 'A' : 'a') + Digit - 10U));
		Value /= (u64)Base;
	} while ((Value != 0U) && (Count < (u32)sizeof(Buffer)));

	while (Width > Count) {
		outbyte(Pad);
		Width--;
	}
	while (Count != 0U) {
		outbyte(Buffer[--Count]);
	}
}

void xil_vprintf(const char8 *Format, va_list Arguments)
{
	while (*Format != '\0') {
		u32 Width = 0U;
		u32 LongCount = 0U;
		char Pad = ' ';
		char Specifier;

		if (*Format != '%') {
			outbyte((char)*Format++);
			continue;
		}

		Format++;
		if (*Format == '%') {
			outbyte('%');
			Format++;
			continue;
		}

		if (*Format == '0') {
			Pad = '0';
			Format++;
		}
		while ((*Format >= '0') && (*Format <= '9')) {
			Width = (Width * 10U) + (u32)(*Format - '0');
			Format++;
		}
		/* xil_printf uses forms such as %.8x; treat precision as width. */
		if (*Format == '.') {
			Format++;
			Width = 0U;
			Pad = '0';
			while ((*Format >= '0') && (*Format <= '9')) {
				Width = (Width * 10U) + (u32)(*Format - '0');
				Format++;
			}
		}
		while (*Format == 'l') {
			LongCount++;
			Format++;
		}

		Specifier = (char)*Format;
		if (*Format != '\0') {
			Format++;
		}

		switch (Specifier) {
		case 'c':
			outbyte((char)va_arg(Arguments, int));
			break;
		case 's': {
			const char *String = va_arg(Arguments, const char *);
			print((const char8 *)((String != (const char *)0) ?
				String : "(null)"));
			break;
		}
		case 'd':
		case 'i': {
			s64 SignedValue;
			u64 Magnitude;

			if (LongCount >= 2U) {
				SignedValue = (s64)va_arg(Arguments, long long);
			} else if (LongCount == 1U) {
				SignedValue = (s64)va_arg(Arguments, long);
			} else {
				SignedValue = (s64)va_arg(Arguments, int);
			}
			if (SignedValue < 0) {
				outbyte('-');
				Magnitude = 0U - (u64)SignedValue;
			} else {
				Magnitude = (u64)SignedValue;
			}
			Cva6PrintUnsigned(Magnitude, 10U, Width, Pad, 0U);
			break;
		}
		case 'u':
		case 'x':
		case 'X': {
			u64 Value;

			if (LongCount >= 2U) {
				Value = (u64)va_arg(Arguments, unsigned long long);
			} else if (LongCount == 1U) {
				Value = (u64)va_arg(Arguments, unsigned long);
			} else {
				Value = (u64)va_arg(Arguments, unsigned int);
			}
			Cva6PrintUnsigned(Value, (Specifier == 'u') ? 10U : 16U,
				Width, Pad, (Specifier == 'X') ? 1U : 0U);
			break;
		}
		case 'p':
			print((const char8 *)"0x");
			Cva6PrintUnsigned((u64)(UINTPTR)va_arg(Arguments, void *),
				16U, (Width != 0U) ? Width : 16U, '0', 0U);
			break;
		default:
			outbyte('%');
			if (Specifier != '\0') {
				outbyte(Specifier);
			}
			break;
		}
	}
}

void xil_printf(const char8 *Format, ...)
{
	va_list Arguments;

	va_start(Arguments, Format);
	xil_vprintf(Format, Arguments);
	va_end(Arguments);
}
