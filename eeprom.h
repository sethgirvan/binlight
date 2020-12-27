/*
 * EEPROM addresses of variables stored in EEPROM.
 *
 * See eep_core.S and eeprom.S
 */

#ifndef EEPROM_H
#define EEPROM_H

/* Default values for the following variables are defined in eep_core.S. */

#define EEP_NORMAL_MODES 0x00
#define EEP_QUICK_MODES 0x08
#define EEP_MODE 0x10
#define EEP_OFF_TIME_VTHRESH 0x11
#define EEP_ON_TIME 0x12
#define EEP_NORMAL_MODES_C 0x13
#define EEP_BAT_LOW_BLINK_INTERVAL 0x14
#define EEP_QUICK_TIME 0x15

/* Flags bit field byte 0 */
#define EEP_FLAGS0 0x16
#define EEP_FLAGS0_ON_TIME 0 /* Set IFF on-time control is used. */
#define EEP_FLAGS0_BAT_LOW_DIM 1 /* Enables low bat dimming. */

#define EEP_QUICK_TO_NONQUICK_MODE 0x17
#define EEP_SF_BRIGHT 0x19
#define EEP_SF_INDICATE_PERIOD 0x1A
#define EEP_SF_INPUT_PERIOD 0x1B
#define EEP_VBAT_LOW_LVLS 0x1C
#define EEP_VBAT_LOW_LVLS_C 4
#define EEP_BAT_LOW_BRIGHT_LVLS 0x20
#define EEP_BAT_LOW_HYST 0x24
#define EEP_OVERTEMP_THRESH 0x25
#define EEP_OVERTEMP_HYST 0x26
#define EEP_VER 0x27

/* A copy of the first EEP_CORE_LEN bytes of the default values is also stored
 * in program memory to allow restoring those values with the unbrick function.
 */
#define EEP_CORE_LEN 0x28

/* Default values for the following variables are defined in eeprom.S. */

#define EEP_INPUT_BIN_STATE_BITC 0x28
#define EEP_INPUT_BIN_STATE_BUF 0x29
#define EEP_SF_STATE 0x2A
#define EEP_SF_STATE_EEPROM_WRITE_LOC 0x2B
#define EEP_UNBRICK_PRESS_CNT 0x2C
#define EEP_BAT_LOW_DIM_LVL 0x2D
#define EEP_HAND_WARMER_TEMP 0x2E

#endif
