Add if possible
---------------
 - Timer. Probably with 10 second granularity.
 - Make indicate_bin() output levels proportional to the actual maximum output
   allowed by the current low battery dimming mode rather than the requested
   duty cycle. Currently indicate_bin() can become essentially unusable when the
   low battery brightness upper bound is less than 50% of the requested
   SF_BRIGHT duty cycle, because both the 100% and 50% levels will be truncated
   to the upper bound.
 - Make pin connections configurable with macros.

Maybe
-----
 - stopwatch
 - Temperature limiting and binary readout by measuring clock drift? Is it even
   possible without an external crystal?
 - Add support for uninitialized RAM bit decay detection hack off-time
   measuring. Checkout https://bazaar.launchpad.net/~toykeeper/flashlight-firmware/trunk/files/head:/Flashy_Mike/otsm-example
 - EEPROM wear-leveling
 - Prescale clock lower for on-time delay detection, etc after initial setup?
 - Programmable strobe frequency (and duty cycle?) for each mode.
 - Mode programming special function like the normal EEPROM write special
   function except it only requires as many bits are necessary to address all
   the modes and it calculates the mode exponentially from the value input, so
   probably only 3 bits of input would be needed. ie something like
     input = '000' -> mode val = 0x01
     input = '001' -> mode val = 0x03
     input = '010' -> mode val = 0x07
     ...
     input = '111' -> mode val = 0xFF
 - Add configuration to only perform low battery indication blinks once instead
   of having to have them repeated on a timer. May not be worthwhile since with
   CFG_BAT_LOW_BLINK_INTERVAL = 255 the blinks only occur every 42.5 minutes.
 - Allow different intervals of low battery blinks at the different VBAT_LOW
   levels.
 - Immediately repeat low battery indication blinks when Vbat drops to a lower
   CFG_VBAT_LOW_LVLS level rather than always waiting for
   CFG_BAT_LOW_BLINK_INTERVAL to completely expire.
 - It may be simpler to use if every special function is just a separate special
   mode. For example, one could have quick mode 4 be vbat_indicate, quick mode
   5 be eeprom_read, quick mode 6 be eeprom_write, etc rather than the current
   'fselect' system where the desired function is input in binary. The special
   functions which take input would need to have a delay before reading the
   input to allow switching past them.
 - Move more stuff out of eep_core.S to cut down on program memory usage for the
   unbrick function.
 - Moonlight mode(s) even dimmer than the min 1/256 duty cycle. Maybe by
   toggling the output from the watchdog interrupt.
 - Time-based "thermal" throttling.
 - Store approximate time left to next low indication battery blinks in EEPROM
   in order to approximately maintain the period between low battery indication
   blinks even when cycling the power (for less than the off-time).
