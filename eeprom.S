/*
 * UNUSED locations are just locations that were being used to for some feature
 * that no longer exists. They can be reused for new features.
 */

.section .eeprom,"ax",@progbits

/* 0x00-0x07 NORMAL_MODES
 * PWM duty cycles. Value 0xFD designates special function mode.
 *
 * Only the first CFG_NORMAL_MODES_C modes are cycled through when switching
 * modes. */
.byte 0x01, 0x04, 0x08, 0x20, 0xFF, 0x40, 0x80, 0xFD

/* 0x08-0x0F QUICK_MODES
 * PWM duty cycles. Value 0xFD designates special function mode.
 *
 * There is no configuration to limit the number of quick modes used because I
 * think repeatedly cycling through the quick modes does not serve much purpose.
 */
.byte 0xFF, 0x40, 0x80, 0xFD, 0xC0, 0x60, 0xD8, 0xA0

/* 0x10
 * MODE
 * Value 0-15. 0-7 is a normal mode, 8-15 is a quick mode.
 */
.byte 0x00

/* 0x11 CFG_OFF_TIME_VTHRESH: Off-time is expired when the off-time capacitor
 * voltage is below
 *   1.1V (internal ref) * CFG_OFF_TIME_VTHRESH / 255
 * on startup.
 *
 * 0xFF seems to result in around 600ms with a 1uF off-time capacitor. May want
 * to try a lower value capacitor. */
.byte 0x66

/* 0x12 CFG_ON_TIME: On-time setting in units of ~10 milliseconds
 * 50 -> 500ms */
.byte 50

/* 0x13 CFG_NORMAL_MODES_C
 * Number of normal modes. eg the value 4 here would mean that after mode 3
 * switching modes cycles back to mode 0.
 * Max 8. ie range [1, 8]. */
.byte 4

/* 0x14 CFG_BAT_LOW_BLINK_INTERVAL: Time between low battery indication blinks
 * in units of ~10 seconds. Set to 0 to disable low battery indication blinks.
 */
.byte 6

/* 0x15 CFG_QUICK_TIME: On-time to select the next quick mode in units of ~10
 * milliseconds: how quickly the switch needs to be double-tapped (in on-off-on
 * sequence: can be a bit awkward on reverse-clicky flashlights) to switch to
 * the next quick mode. */
.byte 10

/* 0x16 CFG_FLAGS0: Configuration flags.
 * bit 0: on-time vs off-time control select
 *        0 - off-time control
 *        1 - on-time control
 * bit 1: BAT_LOW_DIM: If set, limit the maximum brightness during low battery
 *        condition according to CFG_BAT_LOW_BRIGHT_LVLS. The purpose of this
 *        flag when one can just set all CFG_BAT_LOW_BRIGHT_LVLS to 0xFF to get
 *        the same effect is to allow easy enabling and disabling using the
 *        eeprom_write special function. */
.byte 0x02

/* 0x17 CFG_QUICK_TO_NONQUICK_MODE: Which non-quick mode to enter when exiting
 * quick mode.*/
.byte 0

/* 0x18 CFG_SF_BRIGHT_SET_TIME: On-time delay (in units of ~10 ms) until the
 * current brightness (PWM duty cycle) is set as the maximum brightness used for
 * special function mode output. Set to 0 to disable in which case the
 * brightness used for special function mode is fixed to the value set in
 * SF_BRIGHT. */
.byte 250

/* 0x19 SF_BRIGHT: Maximum PWM duty cycle used for indication during special
 * function mode. */
.byte 0x1F

/* 0x1A SF_STATE:  */
.byte 0x08 /* SF_STATE_INIT */

/* 0x1B SF_STATE_EEPROM_WRITE_LOC: EEPROM address (0x00-0x3F) the byte will be
 * written to */
.byte 0x00

/* 0x1C CFG_SF_INDICATE_PERIOD: 1/2 the duration per bit (clock period) of
 * special function mode output (in units of ~10 ms). */
.byte 25

/* 0x1D CFG_SF_INPUT_PERIOD: 1/2 the clock period for special function mode
 * input (in units of ~10 ms). */
.byte 25

/* 0x1E INPUT_BIN_STATE_BITC: Count of bits read in so far by the input_bin()
 * function. */
.byte 0

/* 0x1F INPUT_BIN_STATE_BUF: Buffer of bits read in so far by input_bin(). */
.byte 0

/* 0x20-0x23 CFG_VBAT_LOW_LVLS: 4 (determined by CFG_VBAT_LOW_LVLS_C in main.S)
 * progressively lower battery voltages which determine the activation of
 * different levels of battery indication and dimming (if enabled) when the
 * battery voltage drops below each level.
 *
 * Set all to 0 to disable (eg if your driver does not have a battery voltage
 * sense connection).
 *
 * Using a  V+ -- 19.9k -*- 4.7k -- GND  voltage divider configuration (with no
 * diode in front of the divider):
 *   ADC value = 255 * Vbat * 4.7k / (1.1V * (19.1k + 4.7k))
 * ie:
 *   2.5V * 4.7k / (19.1k + 4.7k) * 255 / 1.1V = ~114.448
 *
 * If you have a diode in front of the divider, eg:
 *   V+ -- D -|>| -- R1 -*- R2 -- GND
 * subtract the forward voltage (Vf) of the diode (usually between around 200mV
 * and 600mV depending on if it is silicon or Schottky) from the battery
 * voltage,
 * ie:
 *   ADC value = 255 * (Vbat - Vf) * R2 / (1.1V * (R1 + R2))
 *
 * The following values are for R1=19.9k, R2=4.7k with no diode.
 */
.byte 137 /* ~3.0V */
.byte 128 /* ~2.8V */
.byte 114 /* ~2.5V */
.byte 92 /* ~2.0V */

/* 0x24-28 CFG_BAT_LOW_BRIGHT_LVLS: Brightness limit levels associated with each
 * of the CFG_VBAT_LOW_LVLS. When active, if the PWM duty cycle would be set
 * above the currently active level, it is truncated to the defined level.
 *
 * This is globally enabled by CFG_FLAGS0_BAT_LOW_DIM.
 *
 * Setting a level to 0xFF implies no brightness limiting at that level (the
 * level can still be useful to have for the low battery indication blinks).
 */
.byte 0xFF
.byte 0x80
.byte 0x40
.byte 0x10
