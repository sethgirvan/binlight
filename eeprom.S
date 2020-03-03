.section .eeprom,"ax",@progbits

/* 0x00-0x07
 * Modes: PWM duty cycles */
.byte 0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F, 0xFF

/* 0x08
 * CTRL
 * bits 0-2: mode selection index (0-7)
 * bits 3-6: unused
 * bit 7: on-time vs off-time control select
 *        0 - off-time control
 *        1 - on-time control */
.byte 0x05

/* 0x09 CFG_OFF_TIME_V_THRESH
 * Max value seems to result in around 600ms with a 1uF off-time capacitor. May
 * want to try a lower value capacitor. */
.byte 0xFF

/* 0x0A CFG_ON_TIME - On-time setting in units of ~10 milliseconds
 * 50 -> 500ms */
.byte 50

/* 0x0B CFG_V_BAT_LOW
 * For a 2.5V setting using a V+ - 19.1k - 4.7k - GND resistor divider:
 *   2.5V * 4.7k / (19.1k + 4.7k) * 255 / 1.1V = ~114.448 */
.byte 114
