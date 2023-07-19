/*
 * The core default values (those that should be restored by the unbrick
 * function) are included from eep_core.S and reside at the beginning of EEPROM.
 * Any other configuration which does cannot inhibit usability is defined after
 * here.
 *
 * If you change the offset of a variable, make sure to update eeprom.h.
 */

.section .eeprom,"ax",@progbits

#include "eep_core.S"

/* 0x28 EEP_INPUT_BIN_STATE_BITC: Count of bits read in so far by the
 * input_bin() function. */
.byte 0

/* 0x29 EEP_INPUT_BIN_STATE_BUF: Buffer of bits read in so far by input_bin().
 */
.byte 0

/* 0x2A EEP_SF_STATE: Special function mode state. */
.byte 0x08 /* SF_STATE_INIT */

/* 0x2B EEP_SF_STATE_EEPROM_WRITE_LOC: EEPROM address (0x00-0x3F) the byte will
 * be written to. */
.byte 0x00

/* 0x2C EEP_UNBRICK_PRESS_CNT: Number of times the switch has been pressed
 * following the unbrick pattern. Once it reaches CFG_UNBRICK_PRESS_REQ, the
 * firmware will be "unbricked" by resetting some core configuration in EEPROM
 * to usable values. See "Unbrick function" in doc/usage.txt. */
.byte 0

/* 0x2D EEP_BAT_LOW_DIM_LVL: Low battery dimming level (index into
 * EEP_VBAT_LOW_LVLS or 255 if voltage is above level 0) persisted across power
 * cycles. This, in conjunction with EEP_BAT_LOW_HYST, ensures that the low
 * battery dimming remains consistent across power cycles. */
.byte 255

/* 0x2E EEP_HAND_WARMER_TEMP: Set temperature for the hand warmer special
 * function. This works the same way as EEP_OVERTEMP_THRESH, see eep_core.S.
 *
 * From the TDK NTCG064EF104FTBX datasheet, it has a resistance of 33.19k at
 * 50 degC.
 *
 * ADC value = 255 / (1 + 47k/33.19k) = ~106
 */
.byte 106 /* 50 degC */
