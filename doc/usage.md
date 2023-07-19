Quick Modes
-----------

Quick modes are entered by cycling power to the driver multiple times in quick
succession: ie with on time less than the `EEP_QUICK_TIME` configuration and off
time less than the normal off time (which depends on the off time capacitance
used and the value of `EEP_OFF_TIME_V_THRESH`).

For example, from any mode the first quick mode can be entered by quickly
turning the light off and on in a sequence of off-on-off-on (or starting with
the light off, on-off-on), the second quick mode with a sequence of
off-on-off-on-off-on, etc.

They are called "quick modes" because they can be entered quickly from any other
mode by quickly tapping the power switch a number of times.

Note that when entering a quick mode, the next normal mode will be entered
intermediately until the power is cycled again. For this reason, it may be
desirable to use less bright modes for the normal modes and more bright modes
for the quick modes if one wants to avoid an intermediate bright flash when
switching to a less bright mode.

Special function mode
---------------------

- Special function mode allows performing one of the following special
  functions:
  - 0 (`0 - 0 - 0`): `vbat_indicate`: Indicate battery voltage
  - 1 (`0 - 0 - 1`): `eeprom_read`: Read from EEPROM
  - 2 (`0 - 1 - 0`): `eeprom_write`: Write to EEPROM
  - 4 (`1 - 0 - 0`): `temp_indicate`: Indicate the temperature
  - 5 (`1 - 0 - 1`): `hard_warmer`: Maintain set hand warmer temperature
  - 7 (`1 - 1 - 1`): `off_time_set`: Set the off-time
  Some special functions that might be implemented in the future:
  - Set timer
  - Stopwatch
  - Set Morse code buffer
  - Output from Morse code buffer

  The special functions `vbat_indicate`, `eeprom_read`, and `temp_indicate`
  output values in binary. From the documentation of the `indicate_bin` function
  those special functions use internally:

      0s are represented as a transition from 0% to 12.5% of SF_BRIGHT and 1s as
      a transition from 50% to 100% of SF_BRIGHT. Bits are output most
      significant bit first. For example for the sequence of 3 bits '011':
      | bit 2  |   bit 1    |  bit 0   |
      0% - 12.5% - 50% - 100% - 50% - 100%

      This scale is used (versus something like 0% to 25% and 50% to 100%) to
      try to match humans' logarithmic-y perception of brightness.

  Upon entering special function mode the bits '0101' are also immediately
  output to let you know you are now in special function mode and to be ready
  to select the special function. '0101' being output looks like a sequence of
  the following brightness levels (as percentage of `SF_BRIGHT`):

      |   0      |     1      |     0      |     1     |
      0% - 12.5% - 50% - 100% - 0% - 12.5% - 50% - 100%

  Then the light will flash three times. Turn the light off and back on during
  each of those flashes to set that respective bit to 1. For example if you
  turn the light off and back on during only the third and final flash, you
  have selected special function '001': `eeprom_read`.

- `vbat_indicate`
   Indicates the raw ADC voltage. If your battery sense connection is as
   following:

       V+ -- 19.1k -*- 4.7k -- GND
                    \
                     \__ADC

   (with no diode in front of the divider), the voltage would be calculated as
   $X/255 * 1.1 * (1 + 19.1/4.7)$ where $X$ is the value between $0$ and $255$
   output by `vbat_indicate`. $1.1$ in the equation is the attiny's 1.1V internal
   voltage reference.

 - `eeprom_write`
   First the light flashes 6 times to allow you to select any of the 64 bytes
   of eeprom you want to overwrite. For example if you turn the light off and
   back on during the first, third, fourth, and fifth flashes, you have selected
   EEPROM address 101110 (hex 0x2E) which is the address of
   `EEP_HAND_WARMER_TEMP`. Immediately after inputting the address you input the
   8 bits of data you want to write to that address. For example if you input
   the binary 01101010 (0x6A) you have set `EEP_HAND_WARMER_TEMP` to value 106,
   which with the default component values corresponds to around 50 degrees
   Celsius.

 - `off_time_set`
   After activating this special function, turn off the light for the desired
   new off-time then turn the light back on. Note that you may not want to use
   this special function while currently in off-time mode because if something
   goes wrong you may be unable to switch modes and thus unable to enter special
   function mode again to adjust things. In that case you will have to use the
   "unbrick function" to reset things to a sane state. So it may be preferable
   to switch to on-time control before using this function.

Low battery indication blinks
-----------------------------

binlight can output a number of blinks on power-on and repeated periodically
to indicate a low battery condition. The frequency at which these low battery
indication blinks are repeated is set by `EEP_BAT_LOW_BLINK_INTERVAL` and the
voltages that the blinks occur at are set by `EEP_VBAT_LOW_LVLS`. Each
progressively lower level of `EEP_VBAT_LOW_LVLS` corresponds with the number of
blinks. ie between `EEP_VBAT_LOW_LVLS[0]` and `EEP_VBAT_LOW_LVLS[1]` the light
will blink just once, between `EEP_VBAT_LOW_LVLS[1]` and `EEP_VBAT_LOW_LVLS[2]`
the light will blink twice, etc.

Low battery dimming
-------------------

binlight can limit the maximum brightness during a low battery condition. The
maximum duty cycles are defined `EEP_BAT_LOW_BRIGHT_LVLS` which are activated
at the corresponding battery voltages defined by `EEP_VBAT_LOW_LVLS`. Bit 1
of `EEP_FLAGS0` provides a global enable switch for low battery dimming, so
one can relatively quickly override low battery dimming on the fly by writing
this bit to 0 with `eeprom_write`.

Unbrick function
----------------

It is possible to mess up the configuration in EEPROM to such a degree that the
light becomes unusable and/or one cannot get back into special function mode to
change the configuration.

The "unbrick" function resets some core configuration in EEPROM to ensure that
the light is usable enough to be able to enter special function mode again to
then adjust the configuration as desired. Thus saving your flashlight from being
a useless brick until/unless you can connect an external programmer to fixup the
EEPROM data.

To activate the unbrick function, turn the light on alternately for less than
.5 (`CFG_UNBRICK_ON_TIME_0`) seconds followed by between .5 and 2
(`CFG_UNBRICK_ON_TIME_1`) seconds a total of 32 (`CFG_UNBRICK_PRESS_REQ`) times
(ie turn the light on for less than .5 seconds then off then on between .5 and 2
seconds then off, repeated 16 times). The unbrick function is based on on-time
only because there is more that can go wrong with off-time measurement (and one
can use this firmware in solely on-time mode with a driver that does not have an
off-time measurement capacitor).

The light indicates the pattern `1-1-0-0` when the unbrick function has
successfully performed.
