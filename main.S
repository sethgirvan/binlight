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
 * MTN-10DD driver board I am using.
 *
 * PB2 (ADC1) is connected through a resistor divider to the battery (Vin). On
 * the MTN-10DD this resistor divider looks like:
 *             _____       ____
 *   (BAT+)---|19.1k|--*--|4.7k|---(BAT-)
 *             -----   |   ----
 *                     |
 *                   (PB2)
 *
 * So the voltage seen at ADC1 = 4.7k / (4.k + 19.1k) ~= .1975 of Vin. ie using
 * the 1.1V internal bandgap reference, the max value from the ADC corresponds
 * to a Vin of ~5.5702V.
 *
 * PB3 (ADC3) connects to the off-time sense capacitor. On the MTN-10DD driver,
 * this is a 1µF capacitor.
 *
 * PB4 (ADC2) connects to a resistor divider containing an NTC thermistor as the
 * lower leg like:
 *
 *             ----       -------
 *   (BAT+)---|4.7k|--*--|10k NTC|---(BAT-)
 *             ----   |   -------
 *                    |
 *                  (PB4)
 */

#include <avr/io.h>

#include "eeprom.h"

#define BIT(n) (1 << (n))

/* Note that some configuration values are stored in EEPROM to allow
 * modification by the user without a programmer by using the eeprom_write
 * special function. The EEPROM addresses for those variables are defined in
 * eeprom.h and the defaults are defined in either eep_core.S or eeprom.S.
 *
 * Some configuration values have not been deemed worth making changeable in
 * this way and thus require recompiling and reflashing to update.
 */

#ifndef F_CPU
/* 4.8Mhz with CKSEL[1:0] bits (two least significant bits of the low fuse byte)
 * set to 0b01. */
#define F_CPU 4800000
#endif

#define MODE_MASK 0xF /* Bits 0-3 indicate current mode out of 16 (0-15). */

/* Modes 0x8 - 0xF (ie when bit 3 is set) are the "quick modes", selected and
 * cycled by switching the power on and off in quick succession (how quick is
 * defined by EEP_QUICK_TIME). */
#define MODE_QUICK 3

/* Special reserved mode duty cycle value which is used for special function
 * mode. This means this duty cycle is not available for use. 0xFD is chosen
 * because the maximum brightness, 0xFF, will be essentially indistinguishable.
 * But 0xFE is also not chosen because for some E-switch-based driver
 * configurations a 100% duty cycle may not work because because the driver
 * power capacitor is only charged while the LED is off, so in that case 0xFE is
 * the maximum usable brightness. */
#define MODE_SF_VAL 0xFD

/* Each time pwm_set() is called the light is briefly turned off while
 * checking the battery voltage, so if it is done at too high of a rate it will
 * perceptibly affect the brightness. Also, pwm_set() steps down the brightness
 * each time it is called while the current temperature exceeds
 * EEP_OVERTEMP_THRESH, so we want to give some time for the temperature to
 * stabilize between each check. */
#define CFG_PWM_SET_INTERVAL 255 /* units of 10 milliseconds */

/* 1/2 period in units of 10 milliseconds of each of the blinks. */
#define CFG_BAT_LOW_BLINK_PERIOD 10

/* States enumeration. States 0x00 through 0x07 are reserved for special
 * functions that can be selected by the user. Auxiliary states that can only be
 * entered internally begin at 0x08. */
#define SF_STATE_VBAT_INDICATE 0x00
#define SF_STATE_EEPROM_READ 0x01
#define SF_STATE_EEPROM_WRITE 0x02
#define SF_STATE_OFF_TIME_SET 0x07
#define SF_STATE_INIT 0x08
#define SF_STATE_FSELECT 0x09 /* Read input to select function */
#define SF_STATE_RETRY_SEL 0x0A
#define SF_STATE_EEPROM_WRITE_VAL 0x0B
/* Set EEP_OFF_TIME_VTHRESH to current off-time ADC value. */
#define SF_STATE_OFF_TIME_SET_CURR 0x0C

/* Determines maximum number of user-selectable special functions. 3 bits allows
 * up to 8 special functions corresponding to SF_STATE enumeration values 0x00
 * through 0x07. */
#define SF_FSELECT_NBITS 3

/* Bit pattern output when entering special function mode: The 4 bits '0101'
 * (output from least to most significant bit, so output as 1 - 0 - 1 - 0). */
#define SF_ENTERED_NBITS 4
#define SF_ENTERED_PATTERN 0x5
/* Bit pattern output to indicate that the special function selection will be
 * retried (output chronologically as 1 - 1 - 0 - 0). */
#define SF_RETRY_SEL_NBITS 4
#define SF_RETRY_SEL_PATTERN 0x3
/* Bit pattern output between battery voltage indications. */
#define SF_VBAT_INDICATE_SYNC_NBITS 4
#define SF_VBAT_INDICATE_SYNC_PATTERN 0x0E
/* Bit pattern output to while waiting for the user to switch off the light in
 * order to set the off time. The number of bits, combined with
 * EEP_SF_INDICATE_PERIOD, determines how long we will wait before cancelling
 * the operation. */
#define SF_OFF_TIME_SET_WAIT_NBITS 8
#define SF_OFF_TIME_SET_WAIT_PATTERN 0xAA

/* We actually use the delta CFG_UNBRICK_ON_TIME_1 - CFG_UNBRICK_ON_TIME_0
 * instead of CFG_UNBRICK_ON_TIME_1 directly, so CFG_UNBRICK_ON_TIME_1 may have
 * a value up to 255 + CFG_UNBRICK_ON_TIME_0. */
#define CFG_UNBRICK_ON_TIME_0 31 /* ~500ms. Units of ~16 milliseconds. */
#define CFG_UNBRICK_ON_TIME_1 125 /* 2000ms. Units of ~16 milliseconds. */
#define CFG_UNBRICK_PRESS_REQ 64
#define CFG_UNBRICK_INDICATE_BRIGHT 0x40 /* Unbrick indication brightness */
#define CFG_UNBRICK_INDICATE_NBITS 4
#define CFG_UNBRICK_INDICATE_PATTERN 0xC

.section .text

/*
 * Register map:
 *   r0: Always 0.
 *   r1: EEP_BAT_LOW_HYST
 *   r2: ISR SREG storage. The value of the Status Register is not automatically
 *       stored and restored when entering and returning from an Interrupt
 *       Service Routine, so r2 is used to store it.
 *   r3: Non-ISR SREG storage.
 *   r5: Quick time remaining: on-time delay (EEP_QUICK_TIME) remaining (in
 *       16ms WD ticks) until the next mode is switched to a non-quick mode.
 *   r6: On-time remaining (in 16ms WD ticks) until the next mode is reset to
 *       mode 0. This will always be 0 when using off-time control.
 *   r7: Unbrick function on-time delay remaining until the unbrick counter will
 *       be incremented.
 *   r8: r7 + r8 = unbrick function on-time delay remaining until the unbrick
 *       counter will be reset.
 *   r9: EEP_BAT_LOW_DIM_LVL
 *   r11: EEP_OVERTEMP_THRESH
 *   r20: Current mode number.
 *   r23: Current mode brightness (PWM duty cycle). The complement of the value
 *        in the output compare register (OCR0B) may differ from this value if
 *        the output is being strobed or it is being modified for special
 *        function mode output indication.
 *   r26: Current unbrick press count (EEP_UNBRICK_PRESS_CNT).
 *   r27: Thermal PWM duty cycle limit.
 */

/*******************************************************************************
 * Interrupt vector table. Make sure to link with -nostdlib when using
 * avr-gcc/GNU ld or avr-libc's vector table will be included and used instead.
 *
 * As a space optimization we stuff the beginning initialization code in the
 * unused interrupt vector locations.
 *
 * Each instruction is commented with the interrupt vector it occupies, but only
 * the watchdog timeout handler is actually used.
 ******************************************************************************/
.global main
main:
	/* Setup registers */
	clr r0 /* reset handler */
	clr r6 /* INT0 handler: unused */
	/* No thermal dimming initially */
	ldi r27, 0xFF /* PCINT0 handler: unused */

	/* Setup output pins */
	sbi _SFR_IO_ADDR(DDRB), PB1 /* timer/counter overflow handler: unused */
	cbi _SFR_IO_ADDR(PORTB), PORTB3 /* EEPROM ready handler: unused */

	/* Disable digital input on ADC pins to save power. */
	ldi r16, BIT(ADC1D) | BIT(ADC2D) | BIT(ADC3D) /* Analog Comparator handler: unused */
	out _SFR_IO_ADDR(DIDR0), r16 /* timer/counter compare match A handler: unused */
	rjmp main_cont /* timer/counter compare match B handler: unused */
	rjmp  int_wd /* watchdog timeout handler */
	reti /* ADC conversion complete handler: unused */

/*******************************************************************************
 * Delay in units of approximately 10 milliseconds.
 * TODO Double-check loop timing.
 *
 * Parameters:
 *   r16: Delay = approximately r16 * 10ms. Not modified.
 * Registers:
 *   r17, r24, r25: temp
 ******************************************************************************/
delay_10ms_tick:
	mov r17, r16
delay_10ms_tick_loop:
	subi r17, 1
	brlo return

	/* Loop iterations = (F_CPU/s / 100 (10ms) - 2 + 1) / 3 (cycles / iter)
	 * The -2 is to account for the time for the final predicate check. The
	 * +1 is to round to the nearest int. */
#define DELAY_10MS_TICK_ITERS ((F_CPU / 100 - 2 + 1) / 3)
	ldi r24, DELAY_10MS_TICK_ITERS % 256
	ldi r25, DELAY_10MS_TICK_ITERS / 256
loop_10ms:
	sbiw r24, 1
	brsh loop_10ms

	rjmp delay_10ms_tick_loop

return:
	ret

/*******************************************************************************
 * Delay in units of approximately 10 seconds.
 *
 * Calls delay_10ms_tick for 2.5 seconds 4 times. Every 2.5 second iteration,
 * pwm_set() is called to handle low battery detection dimming.
 *
 * Parameters:
 *   r19: Delay = approximately r19 * 10s. Not modified.
 * Registers:
 *   r14, r16, r18, r21: temp
 * Indirectly modified registers:
 *   r17, r22, r24, r25, r30
 ******************************************************************************/
delay_10s_tick_pwm_set:
	ldi r16, 250
	mov r18, r19
delay_10s_tick_loop:
	subi r18, 1
	brlo return

	ldi r21, 3
loop_10s:
	rcall delay_10ms_tick

	mov r14, r23
	rcall pwm_set

	subi r21, 1
	brsh loop_10s

	rjmp delay_10s_tick_loop

/*******************************************************************************
 * Write r18 (which should have the ADEN and ADSC bits set high) to ADCSRA,
 * starting a conversion, then wait for the conversion to complete before
 * returning. ADMUX should already be set up and it should have ADLAR set so
 * that the most significant 8 bits can be read from ADCH.
 *
 * Returns:
 *   r18: The result of the conversion.
 ******************************************************************************/
adc_start_read:
	out _SFR_IO_ADDR(ADCSRA), r18

	/* Wait for ADC conversion to finish. It takes a total of 25 ADC clock
	 * cycles for the first conversion, 13 for subsequent conversions. */
adc_wait_loop:
	sbic _SFR_IO_ADDR(ADCSRA), ADSC
	rjmp adc_wait_loop

	in r18, _SFR_IO_ADDR(ADCH)
	ret

/*******************************************************************************
 * Read the off-time capacitor voltage from ADC3 (PB3).
 *
 * Returns:
 *   r18: off-time capacitor voltage.
 ******************************************************************************/
vofft_read:
	/* - Use the internal 1.1V bandgap reference.
	 * - Left adjust the ADC result, so ADCH can just be read to get the
	 *   most significant 8 bits.
	 * - Enable ADC3 (PB3, off-time sense) */
	ldi r18, BIT(REFS0) | BIT(ADLAR) | BIT(MUX1) | BIT(MUX0)
	out _SFR_IO_ADDR(ADMUX), r18
	/* Start a single conversion. Division factor of 32 between the system
	 * clock and the ADC input clock for an ADC input frequency of 150kHz
	 * given a 4.8MHz system clock, within the 200kHz max recommended by the
	 * datasheet. */
	ldi r18, BIT(ADEN) | BIT(ADSC) | BIT(ADPS2) | BIT(ADPS0)
	rjmp adc_start_read /* tail-call optimization */

/*******************************************************************************
 * Read the battery voltage from ADC1 (PB2).
 *
 * Returns:
 *   r18: battery voltage
 ******************************************************************************/
vbat_read:
	/* - Use internal 1.1V bandgap reference
	 * - Left adjust the ADC result, so ADCH can just be read to get the
	 *   most significant 8 bits.
	 * - Enable ADC1 (PB2, Vbat sense pin) */
	ldi r18, BIT(REFS0) | BIT(ADLAR) | BIT(MUX0)
	out _SFR_IO_ADDR(ADMUX), r18

	ldi r18, BIT(ADEN) | BIT(ADSC) | BIT(ADPS2) | BIT(ADPS0)
	rjmp adc_start_read /* tail-call optimization */

/*******************************************************************************
 * Read the temperature from from ADC2 (PB4).
 *
 * Returns:
 *   r18: ADC value indicating the temperature based on the NTC thermistor
 ******************************************************************************/
temp_read:
	/* - Use Vcc as the analog reference.
	 * - Left adjust the ADC result, so ADCH can just be read to get the
	 *   most significant 8 bits.
	 * - Enable ADC2 (PB4, temp sense) */
	ldi r18, BIT(ADLAR) | BIT(MUX1)
	out _SFR_IO_ADDR(ADMUX), r18
	/* Start a single conversion. Division factor of 32 between the system
	 * clock and the ADC input clock for an ADC input frequency of 150kHz
	 * given a 4.8MHz system clock, within the 200kHz max recommended by the
	 * datasheet. */
	ldi r18, BIT(ADEN) | BIT(ADSC) | BIT(ADPS2) | BIT(ADPS0)
	rjmp adc_start_read /* tail-call optimization */

/*******************************************************************************
 * Load a byte from EEPROM
 *
 * Parameters:
 *   r17: EEPROM address of byte to load (0-63)
 * Registers:
 *   r3: SREG storage
 *
 * The resultant byte must be read from IO register EEDR.
 ******************************************************************************/
eeprom_read:
	in r3, _SFR_IO_ADDR(SREG)
	cli

eeprom_read_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp eeprom_read_wait
	out _SFR_IO_ADDR(EEARL), r17
	sbi _SFR_IO_ADDR(EECR), EERE

	out _SFR_IO_ADDR(SREG), r3

	ret

/*******************************************************************************
 * Write a byte to EEPROM
 *
 * Parameters:
 *   r17: EEPROM address to write byte to (0-63)
 *   r18: Value to write
 *
 * Registers:
 *   r3: SREG storage
 ******************************************************************************/
eeprom_write:
	in r3, _SFR_IO_ADDR(SREG)
	cli

eeprom_write_wait:
	sbic _SFR_IO_ADDR(EECR), EEPE
	rjmp eeprom_write_wait
	out _SFR_IO_ADDR(EEARL), r17
	out _SFR_IO_ADDR(EEDR), r18
	sbi _SFR_IO_ADDR(EECR), EEMPE
	sbi _SFR_IO_ADDR(EECR), EEPE

	out _SFR_IO_ADDR(SREG), r3

	ret

/*******************************************************************************
 * Commit new MODE value to EEPROM
 *
 * Parameters:
 *   r18: new MODE value
 * Registers:
 *   r17: tmp
 ******************************************************************************/
mode_commit:
	ldi r17, EEP_MODE
	rcall eeprom_write
	ret

/*******************************************************************************
 * Commit a new SF_STATE value to EEPROM
 *
 * Paremeters:
 *   r18: new SF_STATE value
 * Registerts:
 *   r17: tmp
 ******************************************************************************/
sf_state_commit:
	ldi r17, EEP_SF_STATE
	rcall eeprom_write
	ret

/*******************************************************************************
 * Indicate binary data by flashing the light.
 *
 * 0s are represented as a transition from 0% to 12.5% of SF_BRIGHT and 1s as a
 * transition from 50% to 100% of SF_BRIGHT. For example for the sequence of
 * 3 bits '011' (r17 = 3, r19 = 0x6):
 * | bit 0  |   bit 1    |  bit 2   |
 * 0% - 12.5% - 50% - 100% - 50% - 100%
 *
 * This scale is used (versus something like 0% to 25% and 50% to 100%) to try
 * to match humans' logarithmic-y perception of brightness.
 *
 * Parameters:
 *   r29: Number of bits to indicate (anything past 8 will just be padded with
 *        trailing 0s).
 *   r19: Data to output. The least significant bits are used.
 * Registers:
 *   r10: Duty cycle for first half of bit
 *   r14: Current duty cycle
 *   r16: 1/2 bit time period.
 *   r17: temp
 *   r21: Duty cycle for second half of bit
 *
 * Indirectly modified registers:
 *   r18, r24, r25
 ******************************************************************************/
indicate_bin:
	ldi r17, EEP_SF_INDICATE_PERIOD
	rcall eeprom_read
	in r16, _SFR_IO_ADDR(EEDR)
indicate_bin_loop:
	subi r29, 1
	brlo indicate_bin_restore
	sbrs r19, 0
	rjmp indicate_0
indicate_1:
	/* ~50% */
	mov r10, r23
	lsr r10
	/* If r23 (current mode brightness) is 0x03, we want the brightness to
	 * become 0x02 here since 0x01 would be used for the clock high signal
	 * of indicate_0. */
	inc r10
	/* 100% */
	mov r21, r23
	rjmp indicate_endif
indicate_0:
	/* 0% */
	clr r10
	/* ~12.5% */
	mov r21, r23
	lsr r21
	/* Need to pad the value a bit so that when the lowest allowable
	 * EEP_SF_BRIGHT value (0x03) is used, it becomes 0x01 here instead of
	 * getting truncated to 0. */
	subi r21, -4
	lsr r21
	lsr r21
indicate_endif:
	mov r14, r10
	rcall pwm_set
	rcall delay_10ms_tick
	mov r14, r21
	rcall pwm_set
	rcall delay_10ms_tick

	lsr r19
	rjmp indicate_bin_loop

indicate_bin_restore:
	mov r14, r23
	rcall pwm_set
	ret

/*******************************************************************************
 * Read binary data input by pushing the power switch.
 *
 * For each clock cycle (indicated to the user by flashing the light), if the
 * switch is pressed, a 1 bit is shifted in from the right, otherwise a 0 bit is
 * shifted in from the right.
 *
 * This function stores global state in EEPROM to keep track of which bit it is
 * on, so it is not reentrant.
 *
 * This function only returns once all bits have been read in. If power is reset
 * (due to the user tapping the power switch to input data), keep calling this
 * function until it actually returns.
 *
 * Parameters:
 *   r29: The number of bits to read in.
 *
 * Return:
 *   r19: The bits read in, right adjusted and in chronological order from most
 *        significant to least significant bit.
 *
 * Registers:
 *   r14: Current duty cycle
 *   r16: 1/2 input bit period
 *   r17: temp
 *   r21: Number of bits read on so far
 *
 * Indirectly modified registers:
 *   r18, r23, r24
 ******************************************************************************/
input_bin:
	ldi r17, EEP_SF_INPUT_PERIOD
	rcall eeprom_read
	in r16, _SFR_IO_ADDR(EEDR)

	ldi r17, EEP_INPUT_BIN_STATE_BUF
	rcall eeprom_read
	in r19, _SFR_IO_ADDR(EEDR)

	ldi r17, EEP_INPUT_BIN_STATE_BITC
	rcall eeprom_read
	in r21, _SFR_IO_ADDR(EEDR)

input_bin_loop:
	cp r21, r29
	brsh input_bin_done

	lsl r19
	ori r19, 1
	ldi r17, EEP_INPUT_BIN_STATE_BUF
	mov r18, r19
	rcall eeprom_write
	inc r21
	ldi r17, EEP_INPUT_BIN_STATE_BITC
	mov r18, r21
	rcall eeprom_write

	/* Flash light to provide a clock indication to the user. */
	clr r14
	rcall pwm_set
	rcall delay_10ms_tick
	mov r14, r23
	rcall pwm_set
	rcall delay_10ms_tick

	/* Switch was not pressed: considered a 0 bit. */
	andi r19, ~1
	/* Do not need to commit this to EEPROM yet, since it will be committed
	 * before the next bit is read. */

	rjmp input_bin_loop

input_bin_done:
	/* Done reading bits, reset EEPROM state for future calls. */
	ldi r17, EEP_INPUT_BIN_STATE_BITC
	clr r18
	rcall eeprom_write
	ldi r17, EEP_INPUT_BIN_STATE_BUF
	rcall eeprom_write
	ret

/*******************************************************************************
 * Calculate the next non-quick mode when currently not in a quick mode.
 *
 * Parameters:
 *   r20: Current mode. Not modified.
 * Registers:
 *   r17: temp
 * Return:
 *   r18: Next non-quick mode.
 ******************************************************************************/
nonquick_next:
	mov r18, r20
	inc r18

	ldi r17, EEP_NORMAL_MODES_C
	rcall eeprom_read
	in r17, _SFR_IO_ADDR(EEDR)
	cp r18, r17
	brlo nonquick_next_ovflw_endif

	clr r18

nonquick_next_ovflw_endif:
	ret

/*******************************************************************************
 * Set the next mode to the next nonquick mode.
 *
 * Parameters:
 *   r20: Current mode
 *
 * Registers:
 *   r17, r18: temp
 ******************************************************************************/
set_next_mode_nonquick:
	sbrs r20, MODE_QUICK
	rjmp set_next_nonquick_curr_nonquick

	ldi r17, EEP_QUICK_TO_NONQUICK_MODE
	rcall eeprom_read
	in r18, _SFR_IO_ADDR(EEDR)
	rjmp set_next_nonquick_curr_quick_endif

set_next_nonquick_curr_nonquick:
	rcall nonquick_next

	/* r18 holds next mode */
set_next_nonquick_curr_quick_endif:
	rcall mode_commit
	ret

/*******************************************************************************
 * Until the quick mode on-time delay (EEP_QUICK_TIME) expires, the next mode is
 * set to the next quick mode.
 *
 * Parameters:
 *   r20: Current mode number
 ******************************************************************************/
set_next_mode:
	sbrs r20, MODE_QUICK
	rjmp set_next_curr_nonquick

	/* Currently in quick mode, increment to next quick mode (wrapping). */
	mov r18, r20
	inc r18
	andi r18, MODE_MASK
	ori r18, BIT(MODE_QUICK)
	rjmp mode_next_quick_commit

	/* Not in quick mode, set to first quick mode. */
set_next_curr_nonquick:
	ldi r18, BIT(MODE_QUICK)

mode_next_quick_commit:
	rcall mode_commit

	/* Setup quick mode on-time watchdog interrupt countdown, after the
	 * expiration of which the next mode is set to a nonquick mode. */
	ldi r17, EEP_QUICK_TIME
	rcall eeprom_read
	in r5, _SFR_IO_ADDR(EEDR)

	sei
	ret

/*******************************************************************************
 * Returns:
 *   r30: The current level index in EEP_VBAT_LOW_LVLS or 255 if Vbat is above
 *        EEP_VBAT_LOW_LVLS[0]. Lower battery voltages correspond to higher
 *        indices.
 * Registers:
 *   r17, r18: temp
 ******************************************************************************/
vbat_low_lvl:
	rcall vbat_read /* Vbat in r18 */

	/* Check EEP_VBAT_LOW_LVLS from lowest to highest. */
	ldi r30, EEP_VBAT_LOW_LVLS_C
vbat_low_lvls_loop:
	subi r30, 1
	brlo vbat_low_lvls_loop_end

	mov r17, r30
	subi r17, -EEP_VBAT_LOW_LVLS
	rcall eeprom_read
	in r17, _SFR_IO_ADDR(EEDR)

	/* Hysteresis is applied to increase the threshold required when going
	 * from a higher (lower voltage) to a lower (higher voltage) vbat level.
	 * r9 contains the current low battery dimming level.
	 * We use brlt for a signed comparison because r9 can be -1 which means
	 * no vbat_low_lvl is active. */
	cp r9, r30
	brlt vbat_low_lvls_nohyst
	/* NOTE: We do not check for overflow (to save instructions). It is up
	 * to the user to ensure all EEP_VBAT_LOW_LVLS are
	 * <= 255 - EEP_BAT_LOW_HYST. */
	add r17, r1 /* r1 holds EEP_BAT_LOW_HYST */
vbat_low_lvls_nohyst:
	cp r18, r17
	brsh vbat_low_lvls_loop

vbat_low_lvls_loop_end:
	/* If r9 has changed, update EEP_BAT_LOW_DIM_LVL with its new value. We
	 * spend the extra instructions to check this instead of writing the
	 * value indiscriminately in order to minimize EEPROM wear. */
	cp r30, r9
	breq vbat_low_lvls_update_dim_lvl_endif
	mov r9, r30
	mov r18, r9
	ldi r17, EEP_BAT_LOW_DIM_LVL
	rcall eeprom_write
vbat_low_lvls_update_dim_lvl_endif:
	ret

/*******************************************************************************
 * Set the PWM duty cycle of the light. Configured low battery dimming is
 * enforced.
 *
 * Parameters:
 *   r14: Duty cycle = r14 / 256
 *        The max duty cycle is 255/256 ~= 99.6%. See the comment in
 *        timer_init() about this.
 * Registers:
 *   r17, r22: temp
 *   r27: Thermal PWM limit
 *
 * Returns:
 *   r30: The current level index in EEP_VBAT_LOW_LVLS or 255 if Vbat is above
 *        EEP_VBAT_LOW_LVLS[0]. See vbat_low_lvl().
 *
 * Indirectly modified registers:
 *   r18
 *
 * Because we are using set on compare match mode, lower values of OCR0B result
 * in higher duty cycles, so we need to use 255 minus the passed duty cycle
 * value.
 *
 * The brightness may be halved or doubled (up to duty cycle passed in r14)
 * each time this function is called based on the measured temperature and the
 * thermal throttling limits. It is expected to call this function approximately
 * every 2.5 seconds as a reasonable amount of time between each step-down of
 * the brightness, but the exact timing is not critical.
 ******************************************************************************/
pwm_set:
	/* Check global low bat dimming enable flag */
	ldi r17, EEP_FLAGS0
	rcall eeprom_read
	sbis _SFR_IO_ADDR(EEDR), EEP_FLAGS0_BAT_LOW_DIM
	rjmp vbat_low_endif

	rcall vbat_low_lvl
	cpi r30, EEP_VBAT_LOW_LVLS_C
	brsh vbat_low_endif

	/* Index into EEP_BAT_LOW_BRIGHT_LVLS to determine the brightness
	 * upper bound at this battery level. */
	mov r17, r30
	subi r17, -EEP_BAT_LOW_BRIGHT_LVLS
	rcall eeprom_read
	in r22, _SFR_IO_ADDR(EEDR)

	/* Set the MIN of the current duty cycle and the upper bound duty cycle.
	 */
	cp r14, r22
	brlo vbat_low_endif
	mov r14, r22
vbat_low_endif:

	rcall temp_read

	/* Load EEP_OVERTEMP_HYST into r17 */
	ldi r17, EEP_OVERTEMP_HYST
	rcall eeprom_read
	in r17, _SFR_IO_ADDR(EEDR)

	/* Check if the temperature has dropped below the threshold plus
	 * hysteresis, in which case any enforced thermal throttling is reduced.
	 *
	 * r17 = EEP_OVERTEMP_THRESH + EEP_OVERTEMP_HYST
	 * r18 = ADC value
	 * NOTE: We do not check for overflow here (to save instructions). It is
	 * up to the user to ensure
	 * EEP_OVERTEMP_HYST <= 255 - EEP_OVERTEMP_THRESH. */
	add r17, r11
	cp r18, r17
	 /* Using an NTC thermistor: higher voltage means lower temperature */
	brlo therm_undim_endif
	/* The temperature has dropped below our threshold including hysteresis.
	 * Increase the maximum allowed brightness. */
	lsl  r27
	brcc therm_undim_ovflw_endif /* Handle overflow to saturate at 0xFF */
	ldi r27, 0xFF
therm_undim_ovflw_endif:
therm_undim_endif:

	/* Check if the temperature exceeds the threshold, in which case thermal
	 * throttling is enforced. */
	cp r18, r11 /* EEP_OVERTEMP_THRESH in r11, ADC value in r18 */
	brsh therm_dim_endif

	/* Approximately halve the maximum allowed brightness starting with the
	 * currently set brightness, with minimum duty cycle just above 0. */

	/* Set r27 to the min of r27 and r14 */
	cp r27, r14
	brlo therm_dim_min_endif
	mov r27, r14
therm_dim_min_endif:
	lsr r27
	ori r27, 1
therm_dim_endif:

	/* Enforce thermal maximum duty cycle limit in r27 */
	cp r27, r14
	brsh therm_limit_endif
	mov r14, r27
therm_limit_endif:

	com r14
	out _SFR_IO_ADDR(OCR0B), r14
	ret

/*******************************************************************************
 * Initialize PWM output from pin OC0B (PB1).
 *
 * Parameters:
 *   r23: Duty cycle (0-255)
 * Registers:
 *   r14: Current duty cycle
 *   r17: temp
 * Indirectly modified registers:
 *   r22, r30: pwm_set()
 ******************************************************************************/
timer_init:
	mov r14, r23
	rcall pwm_set
	/* Set OC0B (PB1 on this chip) on compare match, Fast PWM mode (mode 3).
	 *
	 * Note that the set OC0B on compare match ([COM0B1:COM0B0] = '11') mode
	 * means the minimum duty cycle is 0% (OCR0B = 255), and the maximum
	 * duty cycle is ~99.6% (OCR0B = 0). The alternative is clear OC0B on
	 * compare match ([COM0B1:COM0B0] = '10') mode which results in a
	 * minimum duty cycle of ~.4% (OCR0B = 0) and a maximum duty cycle of
	 * 100% (OCR0B = 255).
	 *
	 * I have chosen the set on compare match mode because I want the
	 * ability to output true zero brightness in some cases such as when
	 * indicating binary data. This means that lower OCR0B values result in
	 * a higher duty cycle:
	 *   Duty cycle = (255 - OCR0B) / 256
	 */
	ldi r17, BIT(COM0B1) | BIT(COM0B0) | BIT(WGM01) | BIT(WGM00)
	out _SFR_IO_ADDR(TCCR0A), r17
	/* No clock prescaling. At F_CPU == 4.8MHz, gives a PWM frequency of
	 * 4.8Mhz / 256 (ticks per cycle for 8-bit counter) = 18.75kHz. */
	ldi r17, BIT(CS00)
	out _SFR_IO_ADDR(TCCR0B), r17
	ret

/*******************************************************************************
 * Reset state used by special function mode so it will be properly initialized
 * next time special function mode is entered.
 ******************************************************************************/
sf_reset_state:
	ldi r18, SF_STATE_INIT
	rcall sf_state_commit
	clr r18
	ldi r17, EEP_INPUT_BIN_STATE_BITC
	rcall eeprom_write
	ldi r17, EEP_INPUT_BIN_STATE_BUF
	rcall eeprom_write
	ret

/*******************************************************************************
 * Activate the currently configured mode.
 *
 * The PWM duty cycles associated which each mode are stored at the beginning
 * of EEPROM, so they are directly indexed by the mode number.
 *
 * Parameters:
 *   r20: MODE byte value
 ******************************************************************************/
mode_activate:
	mov r17, r20
	rcall eeprom_read
	in r23, _SFR_IO_ADDR(EEDR)

	cpi r23, MODE_SF_VAL
	breq sf_mode

/*******************************************************************************
 * Normal mode
 ******************************************************************************/
normal_mode:
	rcall timer_init
	rcall sf_reset_state
	rcall set_next_mode

	ldi r17, EEP_BAT_LOW_BLINK_INTERVAL
	rcall eeprom_read
	in r19, _SFR_IO_ADDR(EEDR) /* r19 the is arg to delay_10s_tick */

	/* We periodically call pwm_set() because it handles output dimming when
	 * it detects a low battery condition. It also returns the result of
	 * vbat_low_lvl() in r30.
	 *
	 * Sleep between checks to reduce power usage? */
check_vbat_loop:
	mov r14, r23
	rcall pwm_set
	cpi r30, EEP_VBAT_LOW_LVLS_C
	brsh check_vbat_low_endif

	/* EEP_BAT_LOW_BLINK_INTERVAL = 0 disables low bat indication blinks */
	cpi r19, 0
	brne vbat_low_indicate

check_vbat_low_endif:
	ldi r16, CFG_PWM_SET_INTERVAL
	rcall delay_10ms_tick
	rjmp check_vbat_loop

vbat_low_indicate:
	/* Number of blinks corresponds to the EEP_VBAT_LOW_LVLS index + 1: more
	 * blinks indicates a lower voltage. The single blink for level 0 can
	 * be hard to notice because it just looks like slight delay of the
	 * light turning on, but I have found it fine after getting used to it.
	 */
	ldi r16, CFG_BAT_LOW_BLINK_PERIOD /* arg to delay_10ms_tick */
	mov r31, r30
vbat_low_blink_loop:
	clr r14
	rcall pwm_set
	rcall delay_10ms_tick
	mov r14, r23
	rcall pwm_set
	rcall delay_10ms_tick

	subi r31, 1
	brsh vbat_low_blink_loop

vbat_low_blink_loop_done:
	/* TODO Maybe sleep instead for the period to reduce power usage. */
	rcall delay_10s_tick_pwm_set
	rjmp check_vbat_loop

/*******************************************************************************
 * Output a specific bit pattern which is used to delineate separate chunks of
 * data.
 *
 * Note: May want to consider doing some sort of "out-of-band" indication
 * instead such as completely turning off the light for a period.
 ******************************************************************************/
sf_sync_pattern:
	/* Output a bit pattern after each reading to help the user detect the
	 * start of the next voltage reading.
	 */
	ldi r29, SF_VBAT_INDICATE_SYNC_NBITS
	ldi r19, SF_VBAT_INDICATE_SYNC_PATTERN
	rjmp indicate_bin /* tail-call optimization */

/*******************************************************************************
 * Special function mode
 ******************************************************************************/
sf_mode:
	ldi r17, EEP_SF_BRIGHT
	rcall eeprom_read
	in r23, _SFR_IO_ADDR(EEDR)
	rcall timer_init

	ldi r17, EEP_SF_STATE
	rcall eeprom_read
	in r18, _SFR_IO_ADDR(EEDR)

sf_switch:
	/* r30:r31 make up the Z register used by ijmp */
	ldi r30, pm_lo8(sf_jmp_tbl)
	ldi r31, pm_hi8(sf_jmp_tbl)
	add r30, r18
	adc r31, r0 /* propagate carry */
	ijmp

sf_jmp_tbl:
	/* 8 user-selectable special functions */
	/* 0 */ rjmp sf_state_vbat_indicate
	/* 1 */ rjmp sf_state_eeprom_read
	/* 2 */ rjmp sf_state_eeprom_write
	/* Unused special function slots */
	/* 3 */ rjmp sf_state_retry_sel
	/* 4 */ rjmp sf_state_temp_indicate
	/* 5 */ rjmp sf_state_retry_sel
	/* 6 */ rjmp sf_state_retry_sel
	/* 7 */ rjmp sf_state_off_time_set

	/* Internal states */
	/* 8 */ rjmp sf_state_init
	/* 9 */ rjmp sf_state_fselect
	/* A */ rjmp sf_state_retry_sel
	/* B */ rjmp sf_state_eeprom_write_val
	/* C */ rjmp sf_state_off_time_set_curr


/* Output pattern to indicate that special function selection will be retried.
 */
sf_state_retry_sel:
	/* Can cancel by switching to next mode while this is being output. */
	rcall set_next_mode_nonquick

	ldi r29, SF_RETRY_SEL_NBITS
	ldi r19, SF_RETRY_SEL_PATTERN
	rcall indicate_bin

	ldi r18, SF_STATE_FSELECT
	rcall sf_state_commit
	mov r18, r20
	rcall mode_commit
	rjmp sf_state_fselect

/* Output pattern pattern indicating special function mode has been entered. */
sf_state_init:
	rcall set_next_mode
	ldi r29, SF_ENTERED_NBITS
	ldi r19, SF_ENTERED_PATTERN
	rcall indicate_bin

	ldi r18, SF_STATE_FSELECT
	rcall sf_state_commit

	/* Disable asynchronous on-time-based mode-setting from WD interrupt. */
	clr r5
	/* During the SF entered pattern, SF mode can be exit by switching
	 * modes, but now input will be entered by tapping the power switch, so
	 * to immediately exit special function mode one will have to let the
	 * off-time expire. */
	mov r18, r20
	rcall mode_commit

/* Read input to select function. */
sf_state_fselect:
	ldi r29, SF_FSELECT_NBITS
	rcall input_bin
	/* input_bin() loops internally as necessary until all bits have been
	 * read. */

	mov r18, r19
	rcall sf_state_commit
	rjmp sf_switch

/* Battery voltage is repeatedly indicated in a loop, with some spacer
 * indication to assist with viewer synchronization with the start of each
 * voltage reading. Tapping the power switch at this point will switch to the
 * next mode, exiting special function mode. */
sf_state_vbat_indicate:
	rcall set_next_mode_nonquick

	/* Output the battery voltage repeatedly until the user switches modes.
	 */
vbat_read_loop:
	rcall vbat_read
	mov r19, r18
	ldi r29, 8
	rcall indicate_bin
	rcall sf_sync_pattern
	rjmp vbat_read_loop

/* Read a bytes starting from from a specified EEPROM address. Bytes are
 * continuously output sequentially and looping around from address 0x3F back to
 * 0x00 until the mode is switched.
 *
 * May want to put some sort of synchronization signal between bytes or even
 * output the address before subsequent bytes after the first byte.
 *
 * Registers:
 *   r28: EEPROM address
 */
sf_state_eeprom_read:
	ldi r29, 6 /* 64 bytes of EEPROM on the ATtiny13(a) */
	rcall input_bin
	mov r28, r19
	/* Can switch to next mode now while data is being output. */
	rcall set_next_mode_nonquick
loop_sf_eeprom_read:
	mov r17, r28
	rcall eeprom_read
	in r19, _SFR_IO_ADDR(EEDR)
	ldi r29, 8
	rcall indicate_bin
	inc r28
	andi r28, 0x3F
	rjmp loop_sf_eeprom_read

/* Write a byte to the specified EEPROM address. */
sf_state_eeprom_write:
	/* select address */
	ldi r29, 6
	rcall input_bin
	ldi r17, EEP_SF_STATE_EEPROM_WRITE_LOC
	mov r18, r19
	rcall eeprom_write

	ldi r18, SF_STATE_EEPROM_WRITE_VAL
	rcall sf_state_commit

sf_state_eeprom_write_val:
	/* input byte value */
	ldi r29, 8
	rcall input_bin

	/* write byte */
	ldi r17, EEP_SF_STATE_EEPROM_WRITE_LOC
	rcall eeprom_read
	in r17, _SFR_IO_ADDR(EEDR)
	mov r18, r19
	rcall eeprom_write

	/* Query for user to select another special function. */
	ldi r18, SF_STATE_RETRY_SEL
	rcall sf_state_commit
	rjmp sf_state_retry_sel

/* Temperature is repeatedly indicated in a loop, with some spacer indication to
 * assist with viewer synchronization with the start of each temperature
 * reading. Tapping the power switch at this point will switch to the next mode,
 * exiting special function mode. */
sf_state_temp_indicate:
	rcall set_next_mode_nonquick

	/* Output the temperature repeatedly until the user switches modes. */
temp_read_loop:
	rcall temp_read
	mov r19, r18
	ldi r29, 8
	rcall indicate_bin
	rcall sf_sync_pattern
	rjmp temp_read_loop

/* If the light is switched off while SF_OFF_TIME_SET_WAIT_PATTERN is being
 * output, set EEP_OFF_TIME_VTHRESH to the current value of the off-time ADC
 * upon turning back on.
 *
 * Note that ctrl_off_time includes special code to bypass the off-time
 * expiration when in SF_STATE_OFF_TIME_SET_CURR. Otherwise, it would be
 * impossible to increase the off-time this way because the mode would be reset
 * and thus this special function cancelled when the off-time the user was
 * trying to set exceeded the current off-time.
 */
sf_state_off_time_set:
	ldi r18, SF_STATE_OFF_TIME_SET_CURR
	rcall sf_state_commit
	ldi r29, SF_OFF_TIME_SET_WAIT_NBITS
	ldi r19, SF_OFF_TIME_SET_WAIT_PATTERN
	rcall indicate_bin
	/* User never turned off the light: cancel operation. Query for another
	 * special function. */
	ldi r18, SF_STATE_RETRY_SEL
	rcall sf_state_commit
	rjmp sf_state_retry_sel

sf_state_off_time_set_curr:
	rcall vofft_read
	ldi r17, EEP_OFF_TIME_VTHRESH
	rcall eeprom_write

	/* Query for the user to select another special function. */
	ldi r18, SF_STATE_RETRY_SEL
	rcall sf_state_commit
	rjmp sf_state_retry_sel

/*******************************************************************************
 * main
 *
 * Register usage:
 *   r16:  general temporary values
 *   r20:  MODE byte value from EEPROM
 *   r23:  PWM duty cycle (0-255)
 ******************************************************************************/
main_cont:
	/* Enable watchdog timer interrupt (used for some async operations).
	 * WDP[3:0] left as 0 to give a prescaling of 2048 cycles of the
	 * watchdog (128kHz) timer, resulting in a period of 16ms.
	 *
	 * The global interrupt enable will not be set until the quick mode and
	 * special function brightness set expiration data is set in
	 * set_next_mode(). */
	ldi r16, BIT(WDTIE)
	out _SFR_IO_ADDR(WDTCR), r16

	/* Setup r1 with EEP_BAT_LOW_HYST */
	ldi r17, EEP_BAT_LOW_HYST
	rcall eeprom_read
	in r1, _SFR_IO_ADDR(EEDR)

	/* Setup r9 with the persisted vbat_low_lvl */
	ldi r17, EEP_BAT_LOW_DIM_LVL
	rcall eeprom_read
	in r9, _SFR_IO_ADDR(EEDR)

	/* Setup r11 with EEP_OVERTEMP_THRESH */
	ldi r17, EEP_OVERTEMP_THRESH
	rcall eeprom_read
	in r11, _SFR_IO_ADDR(EEDR)

	/* Handle unbrick function checking
	 * r26: Current unbrick press count */

	ldi r17, EEP_UNBRICK_PRESS_CNT
	rcall eeprom_read
	in r26, _SFR_IO_ADDR(EEDR)

	cpi r26, CFG_UNBRICK_PRESS_REQ
	brlo unbrick_endif

	clr r26 /* Unbrick mode activated: reset press count */

	/* Restore the core EEPROM configuration located in the first
	 * EEP_CORE_LEN bytes of EEPROM. The default values used are stored in
	 * program memory at eep_core. */
	/* r30:r31 make up the Z register used by lpm */
	ldi r30, lo8(eep_core)
	ldi r31, hi8(eep_core)
	clr r17
unbrick_eep_restore_loop:
	cpi r17, EEP_CORE_LEN
	brsh unbrick_eep_restore_loop_end

	lpm r18, Z+ /* Z reg is post-incremented */
	rcall eeprom_write

	inc r17
	rjmp unbrick_eep_restore_loop

unbrick_eep_restore_loop_end:

	/* Indicate unbrick function was performed */
	ldi r23, CFG_UNBRICK_INDICATE_BRIGHT
	rcall timer_init
	ldi r29, CFG_UNBRICK_INDICATE_NBITS
	ldi r19, CFG_UNBRICK_INDICATE_PATTERN
	rcall indicate_bin

	ldi r17, EEP_UNBRICK_PRESS_CNT

unbrick_endif:
	/* Activating unbrick mode requires alternating on-times of less than
	 * CFG_UNBRICK_ON_TIME_0 followed by between CFG_UNBRICK_ON_TIME_0 and
	 * CFG_UNBRICK_ON_TIME_1, so there is different handling for when the
	 * current press count is odd vs even. */
	sbrc r26, 0
	rjmp unbrick_count_odd
unbrick_count_even:
	/* Rather than incrementing and writing r26 to EEPROM here, we save 2
	 * instruction by setting r7 to 1 (instead of 0) and letting the
	 * watchdog interrupt unbrick code do that job the first time it runs.
	 */
	ldi r18, 1
	mov r7, r18
	ldi r18, CFG_UNBRICK_ON_TIME_0
	mov r8, r18
	rjmp unbrick_count_endif
unbrick_count_odd:
	ldi r18, CFG_UNBRICK_ON_TIME_0
	mov r7, r18
	ldi r18, CFG_UNBRICK_ON_TIME_1 - CFG_UNBRICK_ON_TIME_0
	mov r8, r18
unbrick_count_endif:

	/* Read mode */
	ldi r17, EEP_MODE
	rcall eeprom_read
	in r20, _SFR_IO_ADDR(EEDR)

	/* Check whether set to on-time or off-time mode */
	ldi r17, EEP_FLAGS0
	rcall eeprom_read
	sbis _SFR_IO_ADDR(EEDR), EEP_FLAGS0_ON_TIME
	rjmp ctrl_off_time

/*******************************************************************************
 * On-time control
 ******************************************************************************/
ctrl_on_time:
	/* Setup on-time watchdog interrupt countdown, after the expiration of
	 * which the next mode will be reset to mode 0. The interrupt is enabled
	 * in set_next_mode() which is called by mode_activate(). */
	ldi r17, EEP_ON_TIME
	rcall eeprom_read
	in r6, _SFR_IO_ADDR(EEDR)

	rjmp mode_activate

/*******************************************************************************
 * Off-time control
 *
 * Off time senses the amount of time the driver has been off by reading the
 * voltage on capacitor C2. C2 is selected such that while the driver is
 * unpowered, it discharges linearly enough over a sufficient range while
 * unpowered that we can measure the off time with reasonable accuracy over
 * configured off time which is usually somewhere in the range of .25 - 3
 * seconds.
 *
 * Registers:
 * r22 - Configured off-time voltage threshold
 * r21 - Sensed off-time voltage
 ******************************************************************************/
ctrl_off_time:
	/* Bypass off-time expiration check when the off-time is being measured
	 * as part of the SF_STATE_OFF_TIME_SET special function. */
	ldi r17, EEP_SF_STATE
	rcall eeprom_read
	in r18, _SFR_IO_ADDR(EEDR)
	cpi r18, SF_STATE_OFF_TIME_SET_CURR
	breq off_time_endif

off_time_check:
	rcall vofft_read

	/* Charge up off-time sense capacitor for subsequent sensing. */
	sbi _SFR_IO_ADDR(PORTB), PORTB3
	sbi _SFR_IO_ADDR(DDRB), PB3

	/* Load off-time voltage threshold setting from EEPROM */
	ldi r17, EEP_OFF_TIME_VTHRESH
	rcall eeprom_read
	in r22, _SFR_IO_ADDR(EEDR)

	/* If Vsense >= Vthresh */
	cp r18, r22
	brsh off_time_endif

	/* Reset mode */
	clr r20

off_time_endif:
	rjmp mode_activate

/*
 * Watchdog timeout interrupt handler.
 *
 * The watchdog timer prescaler is set such that this interrupt is triggered
 * every 16ms: a 16ms "WD tick".
 *
 * Handles quick mode expiration, special function mode brightness on-time.
 *
 * Registers:
 *   r2: SREG storage
 *   r5: Quick time remaining.
 *   r20: Next nonquick mode
 *   r3 r17, r18: temp; original values restored before returning. (r3 is used
 *                for SREG storage by eeprom_read and eeprom_write.)
 */
int_wd:
	in r2, _SFR_IO_ADDR(SREG)
	push r3
	push r17
	push r18

	/* Quick mode on-time */
	cp r5, r0
	breq wd_quick_mode_endif
	dec r5
	brne wd_quick_mode_expire_endif
	rcall set_next_mode_nonquick
wd_quick_mode_expire_endif:
wd_quick_mode_endif:

	/* On-time */
	cp r6, r0
	breq wd_on_time_endif
	dec r6
	brne wd_on_time_expire_endif
	clr r18
	rcall mode_commit
wd_on_time_expire_endif:
wd_on_time_endif:

	/* Unbrick on-time
	 * r7 is the on-time remaining until we increment the unbrick press
	 * count. r7 + r8 is the on-time remaining until the unbrick press count
	 * expires and is reset back to 0 (we do not start decrementing r8 until
	 * r7 is 0. */
	cp r7, r0
	breq wd_unbrick_inc_endif
	dec r7
	brne wd_unbrick_endif
	inc r26
	rjmp wd_unbrick_count_commit
wd_unbrick_inc_endif:
	cp r8, r0
	breq wd_unbrick_endif
	dec r8
	brne wd_unbrick_endif
	clr r26
wd_unbrick_count_commit:
	ldi r17, EEP_UNBRICK_PRESS_CNT
	mov r18, r26
	rcall eeprom_write
wd_unbrick_endif:

	pop r18
	pop r17
	pop r3
	out _SFR_IO_ADDR(SREG), r2
	reti

.global eep_core
eep_core:
#include "eep_core.S"

.global firmname
firmname:
.asciz "binlight"
