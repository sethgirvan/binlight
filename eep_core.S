/*
 * Core EEPROM data: a copy of this data is stored in both EEPROM and program
 * memory. The copy in program memory is to allow the defaults to be restored to
 * EEPROM when the unbrick function is used.
 *
 * If you change the offset of a variable, make sure to update eeprom.h.
 */

/* 0x00-0x07 EEP_NORMAL_MODES
 * PWM duty cycles. Value 0xFD designates special function mode.
 *
 * Only the first EEP_NORMAL_MODES_C modes are cycled through when switching
 * modes. */
.byte 0x01, 0x04, 0x08, 0x20, 0xFF, 0x40, 0x80, 0xFD

/* 0x08-0x0F EEP_QUICK_MODES
 * PWM duty cycles. Value 0xFD designates special function mode.
 *
 * There is no configuration to limit the number of quick modes used because I
 * think repeatedly cycling through the quick modes does not serve much purpose.
 */
.byte 0xFF, 0x40, 0x80, 0xFD, 0xC0, 0x60, 0xD8, 0xA0

/* 0x10
 * EEP_MODE
 * Value 0-15. 0-7 is a normal mode, 8-15 is a quick mode.
 */
.byte 0x00

/* 0x11 EEP_OFF_TIME_VTHRESH: Off-time is expired when the off-time sense
 * voltage is below
 *   1.1V (internal ref) * EEP_OFF_TIME_VTHRESH / 255
 * on startup.
 *
 * 0x66 seems to result in around 600ms with a 1uF off-time capacitor in the
 * circuit I am using.
 *
 * I have found that the other circuitry connected to the microcontroller can to
 * significantly affect the discharging of the off-time capacitor. eg lower
 * impedance between Vcc and GND seems to increase the discharge rate. This
 * might be due to current being able to flow from the off-time capacitor to the
 * Vcc rail through internal protection diodes in the MCU.
 *
 * You can have this value automatically set based on a measured off-time by
 * using the off_time_set special function.
 */
.byte 0x66

/* 0x12 EEP_ON_TIME: On-time setting in units of ~16 milliseconds.
 * 31 -> 496ms */
.byte 31

/* 0x13 EEP_NORMAL_MODES_C: Number of normal modes. eg the value 4 here would
 * mean that after mode 3 switching modes cycles back to mode 0. Max 8. ie range
 * [1, 8]. */
.byte 4

/* 0x14 EEP_BAT_LOW_BLINK_INTERVAL: Time between low battery indication blinks
 * in units of ~10 seconds. Set to 0 to disable low battery indication blinks.
 */
.byte 6

/* 0x15 EEP_QUICK_TIME: On-time to select the next quick mode in units of ~10
 * milliseconds: how quickly the switch needs to be double-tapped (In on-off-on
 * sequence. Can be a bit awkward on reverse-clicky flashlights.) to switch to
 * the next quick mode. */
.byte 10

/* 0x16 EEP_FLAGS0: Configuration flags.
 * bit 0: EEP_FLAGS0_ON_TIME: on-time vs off-time control select
 *        0 - off-time control
 *        1 - on-time control
 * bit 1: EEP_FLAGS0_BAT_LOW_DIM: If set, limit the maximum brightness during
 *        low battery condition according to EEP_BAT_LOW_BRIGHT_LVLS. The
 *        purpose of this flag when one can just set all EEP_BAT_LOW_BRIGHT_LVLS
 *        to 0xFF to get the same effect is to allow easier enabling and
 *        disabling using the eeprom_write special function. */
.byte 0x03

/* 0x17 EEP_QUICK_TO_NONQUICK_MODE: Which non-quick mode to enter when exiting
 * quick mode.*/
.byte 0

/* 0x18 EEP_SF_BRIGHT_SET_TIME: On-time delay (in units of ~10 ms) until
 * EEP_SF_BRIGHT is set to the current brightness. Set to 0 to disable in which
 * case the value of EEP_SF_BRIGHT is fixed. */
.byte 250

/* 0x19 EEP_SF_BRIGHT: Maximum PWM duty cycle used for indication during special
 * function mode. */
.byte 0x1F

/* 0x1A EEP_SF_INDICATE_PERIOD: 1/2 the duration per bit (clock period) of
 * special function mode output (in units of ~10 ms). */
.byte 25

/* 0x1B EEP_SF_INPUT_PERIOD: 1/2 the clock period for special function mode
 * input (in units of ~10 ms). */
.byte 25

/* 0x1C-0x1F EEP_VBAT_LOW_LVLS: 4 (determined by EEP_VBAT_LOW_LVLS_C in
 * eeprom.h) progressively lower battery voltages which determine the activation
 * of different levels of battery indication and dimming (if enabled) when the
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

/* 0x20-23 EEP_BAT_LOW_BRIGHT_LVLS: Brightness limit levels associated with each
 * of the EEP_VBAT_LOW_LVLS. When active, if the PWM duty cycle would be set
 * above the currently active level, it is truncated to the defined level.
 *
 * This is globally enabled by EEP_FLAGS0_BAT_LOW_DIM.
 *
 * Setting a level to 0xFF implies no brightness limiting at that level (the
 * level can still be useful to have for the low battery indication blinks).
 */
.byte 0xFF
.byte 0x80
.byte 0x40
.byte 0x10

/* 0x24 EEP_VER: Firmware version. Including this in EEPROM allows reading it
 * out at runtime with eeprom_read. */
.byte 1
