.section .eeprom,"ax",@progbits

/* 0x00-0x07
 * Modes: PWM duty cycles */
.byte 0x01, 0x03, 0x07, 0x0F, 0xFF, 0x3F, 0x7F, 0x1F

/* 0x08
 * MODE
 * bits 0-2: mode selection index (0-7)
 * bit 3: reserved for mode increment overflow
 * bits 4-7: unused
 */
.byte 0x05

/* 0x09 CFG_OFF_TIME_V_THRESH
 * Max value seems to result in around 600ms with a 1uF off-time capacitor. May
 * want to try a lower value capacitor. */
.byte 0xFF

/* 0x0A CFG_ON_TIME: On-time setting in units of ~10 milliseconds
 * 50 -> 500ms */
.byte 50

/* 0x0B CFG_V_BAT_LOW
 * For a 2.5V setting using a V+ - 19.1k - 4.7k - GND resistor divider:
 *   2.5V * 4.7k / (19.1k + 4.7k) * 255 / 1.1V = ~114.448 */
.byte 114

/* 0x0C UNUSED */
.byte 0x00

/* 0x0D CFG_QUICK_TIME: On-time to select the next quick mode in units of ~10
 * milliseconds: how quickly the switch needs to be double-tapped (in on-off-on
 * sequence: can be a bit awkward on reverse-clicky flashlights) to switch to
 * the next quick mode. */
.byte 10

/* 0x0E CFG_FLAGS0: Configuration flags.
 * bit 0: on-time vs off-time control select
 *        0 - off-time control
 *        1 - on-time control */
.byte 0x00

/* 0x0F CFG_QUICK_TO_NONQUICK_MODE: Which non-quick mode to enter when exiting
 * quick mode.*/
.byte 0

/* 0x10 CFG_SF_BRIGHT_SET_TIME: On-time delay (in units of ~10 ms) until the
 * current brightness (PWM duty cycle) is set as the maximum brightness used for
 * special function mode output. This delay is in addition to the CFG_QUICK_TIME
 * delay. Set to 0 to disable in which case the brightness used for special
 * function mode is fixed to the value set in PRGM_BRIGHT. */
.byte 250

/* 0x11 SF_BRIGHT: Maximum PWM duty cycle used for indication during special
 * function mode. */
.byte 0x1F
