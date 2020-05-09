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

/* 0x25 EEP_INPUT_BIN_STATE_BITC: Count of bits read in so far by the
 * input_bin() function. */
.byte 0

/* 0x26 EEP_INPUT_BIN_STATE_BUF: Buffer of bits read in so far by input_bin().
 */
.byte 0

/* 0x27 EEP_SF_STATE: Special function mode state. */
.byte 0x08 /* SF_STATE_INIT */

/* 0x28 EEP_SF_STATE_EEPROM_WRITE_LOC: EEPROM address (0x00-0x3F) the byte will
 * be written to. */
.byte 0x00

/* 0x29 EEP_UNBRICK_PRESS_CNT: Number of times the light has been switched off
 * within CFG_UNBRICK_ON_TIME. Once it reaches CFG_UNBRICK_PRESS_REQ, the
 * firmware will be "unbricked" by resetting some core configuration in EEPROM
 * to usable values. */
.byte 0
