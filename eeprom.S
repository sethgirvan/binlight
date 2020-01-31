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
.byte 0x85
