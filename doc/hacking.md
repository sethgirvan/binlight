In a normal (non E-switch) flashlight, the switch simply selects allowing power
to the driver or completely cutting power to it. This makes programming a user
interface based on presses of the switch a bit awkward since every time the
program is executed it needs to figure out if it was just reset due to the
switch being pressed as part of some meaningful input. The two types of state
information used here are on-time and off-time.

on-time
-------

The basic mechanism of on-time control is that it is determined that during some
point in the program execution the user turning the light off and back on will
have some meaning. The basic way this is implemented here is:

- Store in EEPROM the state data that when read on startup indicates that the
  switch was tapped (the light was turned off and back on). Then wait for the
  specified on-time delay and set the state in EEPROM to indicate that the
  switch was not pressed. If the switch was pressed during the on-time delay,
  the state in EEPROM will setup correspondingly.

off-time
--------

The software side of off-time control is a bit more intuitive than on-time
control. We just check the voltage at the off-time capacitor which can be
approximately mapped to how long the driver was unpowered, then set the state
accordingly based on whether the light was off for longer or shorter than the
specified off-time interval.
