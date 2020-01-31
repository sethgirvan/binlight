/*
 * This is free and unencumbered software released into the public domain.
 *
 * Anyone is free to copy, modify, publish, use, compile, sell, or
 * distribute this software, either in source code form or as a compiled
 * binary, for any purpose, commercial or non-commercial, and by any
 * means.
 *
 * In jurisdictions that recognize copyright laws, the author or authors
 * of this software dedicate any and all copyright interest in the
 * software to the public domain. We make this dedication for the benefit
 * of the public at large and to the detriment of our heirs and
 * successors. We intend this dedication to be an overt act of
 * relinquishment in perpetuity of all present and future rights to this
 * software under copyright law.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 * OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 * For more information, please refer to <http://unlicense.org/>
 *
 *
 * Firmware for ATtiny13 and ATtiny85 -based flashlight drivers that includes
 * some interesting features while still fitting in the meager 1KiB of flash
 * program memory on the ATtiny13.
 *
 * For pinouts and registers referenced in this code, see the ATtiny13
 * datasheet: http://ww1.microchip.com/downloads/en/DeviceDoc/doc8126.pdf
 *
 * PB1 (OC0B) is is connected to the MOSFET gate and thus controls the LED on
 * the MTN-10DD driver board.
 */

#include <avr/io.h>

#ifndef F_CPU
#define F_CPU 4800000 /* With fuse bits set to high: 0xFF low: 0x75, */
#endif

#define CTRL_ADDR 0x08
#define CTRL_MODE_MASK 0x7
#define CTRL_ON_TIME 7

.section .text

/*
 * Register usage:
 * r16 - general temporary values
 * r23 - PWM duty cycle (0-255)
 */

.global main
main:
	/* Setup output pin */
	sbi _SFR_IO_ADDR(DDRB), PB1

/* Check whether set to on-time or off-time mode */
	ldi r16, CTRL_ADDR
	out _SFR_IO_ADDR(EEARL), r16
	sbi _SFR_IO_ADDR(EECR), EERE
	in r16, _SFR_IO_ADDR(EEDR)
	sbrs r16, CTRL_ON_TIME
	rjmp ctrl_off_time

ctrl_on_time:
	andi r16, CTRL_MODE_MASK
	out _SFR_IO_ADDR(EEARL), r16
	sbi _SFR_IO_ADDR(EECR), EERE
	in r23, _SFR_IO_ADDR(EEDR)
	rjmp timer_init

ctrl_off_time:

timer_init:
	/* Clear OC0B (PB1 on this chip) on compare match, Fast PWM mode (mode
	 * 3). */
	ldi r16, 0x23
	out _SFR_IO_ADDR(TCCR0A), r16
	/* No clock prescaling. At F_CPU == 4.8MHz, gives a PWM frequency of
	 * 4.8Mhz / 256 (ticks per cycle for 8-bit counter) = 18.75kHz*/
	ldi r16, 0x01
	out _SFR_IO_ADDR(TCCR0B), r16
	out _SFR_IO_ADDR(OCR0B), r23
inf_loop:
	rjmp inf_loop

.global verstr
verstr:
.asciz "snth-10dd v0.0.1"
