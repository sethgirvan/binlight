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
 */

/*
 * Firmware for ATtiny13(a) and ATtiny85 -based flashlight drivers that includes
 * some interesting features while still fitting in the 1KiB of flash program
 * memory on the ATtiny13.
 *
 * For pinouts and registers referenced in this code, see the ATtiny13a
 * datasheet: http://ww1.microchip.com/downloads/en/DeviceDoc/doc8126.pdf
 *
 * PB1 (OC0B) is connected to the MOSFET gate and thus controls the LED on the
 * MTN-10DD driver board.
 *
 * PB3 (ADC3) connects to the off-time sense capacitor. On the MTN-10DD driver,
 * this is a 10µF capacitor, but I find this gives too large of a minimum
 * off-time, so I am using a 1µF capacitor I am finding to result in a minimum
 * off-time of ~600ms.
 */

#include <avr/io.h>

#define BIT(n) (1 << (n))

#ifndef F_CPU
/* 4.8Mhz with CKSEL[1:0] bits (two least significant bits of the low fuse byte)
 * set to 0b01. */
#define F_CPU 4800000
#endif

#define MODE_ADDR 0x08
#define MODE_MASK 0x7 /* Bits 0-2 indicate current mode out of 8 (0-7). */
/* Modes 0x4 - 0x7 (ie when bit 2 is set) are the "quick modes", selected and
 * cycled by switching the power on and off in quick succession (how quick is
 * defined by CFG_QUICK_TIME). */
#define MODE_QUICK 2
#define MODE_OVERFLOW 3 /* MODE bit 3 reserved for mode bits overflow. */

#define CFG_OFF_TIME_V_THRESH_ADDR 0x09
#define CFG_ON_TIME_ADDR 0x0A
#define CFG_V_BAT_LOW 0x0B
#define CFG_QUICK_TIME_ADDR 0x0D

/* Bit field flags byte 0 */
#define CFG_FLAGS0_ADDR 0x0E
#define CFG_FLAGS0_ON_TIME 0 /* 1 IFF on-time control is configured. */

#define CFG_QUICK_TO_NONQUICK_MODE_ADDR 0x0F
#define CFG_SF_BRIGHT_SET_TIME_ADDR 0x10

#define SF_BRIGHT_ADDR 0x11

#define DEBUG_BYTE_ADDR 0x3F

.section .text

/*******************************************************************************
 * Interrupt vector table. Make sure to link with -nostdlib when using
 * avr-gcc/GNU ld or avr-libc's vector table will be included and used instead.
 * TODO Can stuff program code in unused locations.
 ******************************************************************************/
rjmp main /* reset handler */
reti /* INT0 handler: unused */
reti /* PCINT0 handler: unused */
reti /* timer/counter overflow handler: unused */
reti /* EEPROM ready handler: unused */
reti /* Analog Comparator handler: unused */
reti /* timer/counter compare match A handler: unused */
reti /* timer/counter compare match B handler: unused */
reti /* watchdog timeout handler: unused */
reti /* ADC conversion complete handler: unused */

/*******************************************************************************
 * Write a value to the last byte (63) of the EEPROM to later be read out with
 * an external programmer for debugging purposes.
 *
 * Parameters:
 *   r18 - byte value
 ******************************************************************************/
debug_byte_eeprom:
	ldi r17, DEBUG_BYTE_ADDR
dbe_eeprom_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp dbe_eeprom_wait
	out _SFR_IO_ADDR(EEARL), r17
	out _SFR_IO_ADDR(EEDR), r18
	sbi _SFR_IO_ADDR(EECR), EEMPE
	sbi _SFR_IO_ADDR(EECR), EEPE
	ret

/*******************************************************************************
 * Delay in units of approximately 10 milliseconds.
 * TODO Double-check loop timing.
 *
 * Parameters:
 *   r16: Delay approximately = r16 * 10ms
 * Registers used:
 *   r17, r24, r25
 ******************************************************************************/
delay_10ms_tick:
	clr r17
loop_delay:
	clr r24
	clr r25
loop_10ms:
	adiw r24, 1
	/* 4800000Hz * .01s / 256 (adiw of r24 per increment of r25) /
	 * 3 (cycles per loop) = 62.5. Round down since we have already overshot
	 * due to setup time. */
	cpi r25, 62
	brlo loop_10ms

	inc r17
	cp r16, r17
	brsh loop_delay
	ret

/*******************************************************************************
 * Load a byte from EEPROM
 *
 * Parameters:
 *   r17: EEPROM address of byte to load (0-63)
 *
 * The resultant byte must be read from IO register EEDR.
 ******************************************************************************/
eeprom_read:
eeprom_read_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp eeprom_read_wait
	out _SFR_IO_ADDR(EEARL), r17
	sbi _SFR_IO_ADDR(EECR), EERE
	ret

/*******************************************************************************
 * Write a byte to EEPROM
 *
 * Parameters:
 *   r17: EEPROM address to write byte to (0-63)
 *   r18: Value to write
 ******************************************************************************/
eeprom_write:
eeprom_write_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp eeprom_write_wait
	out _SFR_IO_ADDR(EEARL), r17
	out _SFR_IO_ADDR(EEDR), r18
	sbi _SFR_IO_ADDR(EECR), EEMPE
	sbi _SFR_IO_ADDR(EECR), EEPE
	ret

/*******************************************************************************
 * Commit new MODE value to EEPROM
 *
 * Parameters:
 *   r20: new MODE value
 * Registers:
 *   r17, r18: tmp
 ******************************************************************************/
mode_commit:
	mov r18, r20
	ldi r17, MODE_ADDR
	rcall eeprom_write
	ret

/*******************************************************************************
 * Activate the currently configured mode.
 *
 * Parameters:
 *   r16: MODE byte value
 ******************************************************************************/
mode_activate:
	/* Read duty cycle for configured mode number */
	andi r16, MODE_MASK
ma_eeprom_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp ma_eeprom_wait
	out _SFR_IO_ADDR(EEARL), r16
	sbi _SFR_IO_ADDR(EECR), EERE
	in r23, _SFR_IO_ADDR(EEDR)

timer_init:
	/* Clear OC0B (PB1 on this chip) on compare match, Fast PWM mode (mode
	 * 3). */
	ldi r16, BIT(COM0B1) | BIT(WGM01) | BIT(WGM00)
	out _SFR_IO_ADDR(TCCR0A), r16
	/* No clock prescaling. At F_CPU == 4.8MHz, gives a PWM frequency of
	 * 4.8Mhz / 256 (ticks per cycle for 8-bit counter) = 18.75kHz */
	ldi r16, BIT(CS00)
	out _SFR_IO_ADDR(TCCR0B), r16
	out _SFR_IO_ADDR(OCR0B), r23
	ret

/*******************************************************************************
 * main
 *
 * Register usage:
 *   r16:  general temporary values
 *   r20:  MODE byte value from EEPROM
 *   r23:  PWM duty cycle (0-255)
 ******************************************************************************/
.global main
main:
	/* Setup output pins */
	ldi r16, BIT(PB1)
	out _SFR_IO_ADDR(DDRB), r16
	/* sbi _SFR_IO_ADDR(DDRB), PB1 */
	cbi _SFR_IO_ADDR(PORTB), PORTB3
	/* Disable digital input on our ADC pins to save power. */
	ldi r16, BIT(ADC3D) | BIT(ADC1D)
	out _SFR_IO_ADDR(DIDR0), r16

	/* Read mode */
	ldi r17, MODE_ADDR
	rcall eeprom_read
	in r20, _SFR_IO_ADDR(EEDR)

	/* Check whether set to on-time or off-time mode */
	ldi r17, CFG_FLAGS0_ADDR
	rcall eeprom_read
	in r19, _SFR_IO_ADDR(EEDR)
	sbrs r19, CFG_FLAGS0_ON_TIME
	rjmp ctrl_off_time

/*******************************************************************************
 * On-time control
 ******************************************************************************/
ctrl_on_time:
	mov r16, r20 /* save current mode in r16 */
	rcall mode_activate
	inc r20
	andi r20, ~BIT(MODE_OVERFLOW)
	rcall mode_commit

	/* Read on-time setting into r16. */
	ldi r16, CFG_ON_TIME_ADDR
cont_eeprom_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp cont_eeprom_wait
	out _SFR_IO_ADDR(EEARL), r16
	sbi _SFR_IO_ADDR(EECR), EERE
	in r16, _SFR_IO_ADDR(EEDR)
	/* Wait on-time interval before resetting mode. Delay time is in r16. */
	rcall delay_10ms_tick

/* Reset mode */
	andi r20, ~MODE_MASK
	rcall mode_commit

	rjmp inf_loop

/*******************************************************************************
 * Off-time control
 *
 * Off time senses the amount of time the driver has been off by reading the
 * voltage on capacitor C2. C2 is selected such that while the driver is
 * unpowered, it discharges linearly enough over a sufficient range while
 * unpowered that we can measure the off time with reasonable accuracy over
 * configured off time which is usually somewhere in the range of .25 - 2
 * seconds.
 *
 * Registers:
 * r22 - Configured off-time voltage threshold
 * r21 - Sensed off-time voltage
 ******************************************************************************/
ctrl_off_time:
	/* Setup the ADC for off-time sensing
	 * - Use the internal 1.1V bandgap reference.
	 * - Left adjust the ADC result, so ADCH can just be read to get the
	 *   most significant 8 bits.
	 * - Enable ADC3 (PB3, off-time sense) */
	ldi r16, BIT(REFS0) | BIT(ADLAR) | BIT(MUX1) | BIT(MUX0)
	out _SFR_IO_ADDR(ADMUX), r16
	/* Start a single conversion. Division factor of 32 between the system
	 * clock and the ADC input clock for an ADC input frequency of 150kHz
	 * given a 4.8MHz system clock, within the 200kHz max recommended by the
	 * datasheet. */
	ldi r16, BIT(ADEN) | BIT(ADSC) | BIT(ADPS2) | BIT(ADPS0)
	out _SFR_IO_ADDR(ADCSRA), r16

	/* Load off-time voltage threshold setting from EEPROM */
	ldi r17, CFG_OFF_TIME_V_THRESH_ADDR
	rcall eeprom_read
	in r22, _SFR_IO_ADDR(EEDR)

	/* Wait for ADC conversion to finish. It takes a total of 25 ADC clock
	 * cycles here. */
off_time_adc_wait:
	sbic _SFR_IO_ADDR(ADCSRA), ADSC
	rjmp off_time_adc_wait

	in r21, _SFR_IO_ADDR(ADCH)
	/* Debugging: store ADC val in EEPROM debug byte. */
	mov r18, r21
	rcall debug_byte_eeprom

	/* Charge up off-time sense capacitor for subsequent sensing. */
	sbi _SFR_IO_ADDR(PORTB), PORTB3
	sbi _SFR_IO_ADDR(DDRB), PB3

	/* If Vsense >= Vthresh */
	cp r21, r22
	brsh off_time_endif

	/* Reset mode */
	andi r20, ~MODE_MASK

off_time_endif:
	/* r16 contains current MODE value, r20 will be next MODE value. */
	mov r16, r20
	rcall mode_activate

/*
 * Until the quick mode on-time delay (CFG_QUICK_TIME) expires, the next mode is
 * set to the next quick mode.
 */
mode_next_quick:
	sbrs r20, MODE_QUICK
	rjmp curr_nonquick

	/* Currently in quick mode, increment to next quick mode (wrapping). */
	cpi r20, 0x07
	brlo mode_quick_inc
	ldi r20, 0x04
	rjmp mode_quick_ovflw_endif
mode_quick_inc:
	inc r20
mode_quick_ovflw_endif:
	/* Store next non-quick mode on the stack. It will be used if the quick
	 * mode delay expires. */
	ldi r17, CFG_QUICK_TO_NONQUICK_MODE_ADDR
	rcall eeprom_read
	in r17, _SFR_IO_ADDR(EEDR)
	push r17
	rjmp mode_next_quick_commit

	/* Not in quick mode, set to first quick mode. */
curr_nonquick:
	cpi r20, 0x03
	brlo nonquick_inc
	clr r20
	rjmp nonquick_ovflw_endif
nonquick_inc:
	inc r20
nonquick_ovflw_endif:
	/* Push next non-quick mode to be restored if quick mode delay expires.
	 */
	push r20
	ldi r20, 0x04

mode_next_quick_commit:
	rcall mode_commit

	/* Wait for quick mode interval to expire, then set next mode to non
	 * quick mode. */

	ldi r17, CFG_QUICK_TIME_ADDR
	rcall eeprom_read
	in r16, _SFR_IO_ADDR(EEDR)
	rcall delay_10ms_tick

	/* Restore pushed non-quick mode. */
	pop r20
	rcall mode_commit

	/* Wait for CFG_SF_BRIGHT_SET_TIME, then set SF_BRIGHT to the current
	 * PWM duty cycle value. If CFG_SF_BRIGHT_SET_TIME is 0, this is
	 * disabled. */
	ldi r17, CFG_SF_BRIGHT_SET_TIME_ADDR
	rcall eeprom_read
	in r16, _SFR_IO_ADDR(EEDR)
	cpi r16, 0
	breq prgm_bright_set_endif
	rcall delay_10ms_tick
	ldi r17, SF_BRIGHT_ADDR
	in r18, _SFR_IO_ADDR(OCR0B)
	rcall eeprom_write
prgm_bright_set_endif:

inf_loop:
	rjmp inf_loop

.global verstr
verstr:
.asciz "snth-10dd v0.0.1"
