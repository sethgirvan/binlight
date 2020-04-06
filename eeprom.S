/*
 * UNUSED locations are just locations that were being used to for some feature
 * or something that no longer exists. They can be reused for new features.
 */

.section .eeprom,"ax",@progbits

/* 0x00-0x07
 * Modes: PWM duty cycles */
.byte 0x01, 0x04, 0x08, 0x20, 0xFF, 0x40, 0x80, 0xFD

/* 0x08
 * MODE
 * bits 0-2: mode selection index (0-7)
 * bit 3: reserved for mode increment overflow
 * bits 4-7: unused
 */
.byte 0x00

/* 0x09 CFG_OFF_TIME_VTHRESH: Off-time is expired when the off-time capacitor
 * voltage is below
 *   1.1V (internal ref) * CFG_OFF_TIME_VTHRESH / 255
 * on startup.
 *
 * 0xFF seems to result in around 600ms with a 1uF off-time capacitor. May want
 * to try a lower value capacitor. */
.byte 0xFF

/* 0x0A CFG_ON_TIME: On-time setting in units of ~10 milliseconds
 * 50 -> 500ms */
.byte 50

/* 0x0B CFG_VBAT_LOW: Low battery indication and dimming (if enabled) is
 * activated below this voltage. Set to 0 to disable (eg if your driver does not
 * have a battery voltage sense connection).
 *
 * For a 2.5V setting using a V+ - 19.1k - 4.7k - GND resistor divider:
 *   2.5V * 4.7k / (19.1k + 4.7k) * 255 / 1.1V = ~114.448 */
.byte 114

/* 0x0C CFG_BAT_LOW_BLINK_INTERVAL: Time between low battery indication blinks
 * in units of ~10 seconds. Set to 0 to disable low battery indication blinks.
 */
.byte 6

/* 0x0D CFG_QUICK_TIME: On-time to select the next quick mode in units of ~10
 * milliseconds: how quickly the switch needs to be double-tapped (in on-off-on
 * sequence: can be a bit awkward on reverse-clicky flashlights) to switch to
 * the next quick mode. */
.byte 10

/* 0x0E CFG_FLAGS0: Configuration flags.
 * bit 0: on-time vs off-time control select
 *        0 - off-time control
 *        1 - on-time control
 * bit 1: BAT_LOW_DIM: If set, progressively lower max brightness limit during
 *        low battery condition.
 */
.byte 0x02

/* 0x0F CFG_QUICK_TO_NONQUICK_MODE: Which non-quick mode to enter when exiting
 * quick mode.*/
.byte 0

/* 0x10 CFG_SF_BRIGHT_SET_TIME: On-time delay (in units of ~10 ms) until the
 * current brightness (PWM duty cycle) is set as the maximum brightness used for
 * special function mode output. This delay is in addition to the CFG_QUICK_TIME
 * delay. Set to 0 to disable in which case the brightness used for special
 * function mode is fixed to the value set in SF_BRIGHT. */
.byte 250

/* 0x11 SF_BRIGHT: Maximum PWM duty cycle used for indication during special
 * function mode. */
.byte 0x1F

/* 0x12 SF_STATE:  */
.byte 0x08 /* SF_STATE_INIT */

/* 0x13 SF_STATE_EEPROM_WRITE_LOC: EEPROM address (0x00-0x3F) the byte will be
 * written to */
.byte 0x00

/* 0x14 CFG_SF_INDICATE_PERIOD: 1/2 the duration per bit (clock period) of
 * special function mode output (in units of ~10 ms). */
.byte 25

/* 0x15 CFG_SF_INPUT_PERIOD: 1/2 the clock period for special function mode
 * input (in units of ~10 ms). */
.byte 25

/* 0x16 INPUT_BIN_STATE_BITC: Count of bits read in so far by the input_bin()
 * function. */
.byte 0

/* 0x17 INPUT_BIN_STATE_BUF: Buffer of bits read in so far by input_bin(). */
.byte 0
