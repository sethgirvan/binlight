binlight
========

Firmware for ATtiny13(A) and ATtiny85 (and probably other AVRs) -based
flashlight drivers. It is written in AVR assembly and includes some some unusual
features while still fitting in the meager 1KiB of flash program memory on the
ATtiny13A.

Features
--------

 - On or off -time based standard mode switching.
 - "Quick modes" which can be directly entered from any other mode by a
   sequence of quick consecutive button taps.
 - Configurable multi-level low-battery brightness limiting and periodic
   indication blinks.
 - The following "special function modes" with input/output performed with
   binary sequences of button taps/light flashes.
   - battery voltage readout
   - read data at any location in EEPROM
   - write data to any EEPROM location
   - temperature readout
   - "hand warmer" mode to maintain target temperature
   - measure and set new off-time

   The UI is pretty rough. Input and output is binary, and voltage and
   temperature readouts are raw ADC values which you can then calculate the
   voltage and temperature in degrees from based on component values used.

   By changing the bytes in EEPROM with the `eeprom_write` special function,
   almost all configuration values, including mode settings, can be changed on
   the fly without reprogramming.

   The binary-based input/output interface is arguable a bit ridiculous, but
   it may amuse one's inner hacker.

binlight was initially written for the ATtiny13A-based Mountain
Electronics MTN-10DD driver board. This 10mm diameter board uses an ATtiny13A
in the 10-MLP (10-VFDFN) package which cannot be easily connected to for
in-circuit programming the way the common 8-SOIC package can with a SOIC clip.
The inconvenience of having to reflow the chip from the board for every firmware
change inspired the high level of run-time configurability of this firmware.

License
-------

binlight is completely free and public domain. See the LICENSE file.

Requirements
------------

 - avr-gcc
 - avr-libc (Only for preprocessor macros: avr-libc is not linked with the
   program.)
 - avr-binutils
 - avrdude (for flashing the microcontroller)

Building
--------

Ensure the required dependencies above are installed. Change the line

    MCU ?= attiny13a

in the Makefile if you are using a different microcontroller than the ATtiny13A.
See `--mmcu` option documentation in `man 1 avr-gcc` for the list of
microcontroller names.

Then run `make` to generate the Intel hex (.ihex) files that can then be flashed
to the microcontroller.

Flashing
--------

Change the line

    AVRDUDE_MCU ?= t13

in the Makefile if you are using a different microcontroller than the ATtiny13A.
Run `avrdude -p ?` to get the list of avrdude microcontroller names.

Change the line

    PROGRAMER ?= usbasp

in the Makefile if you are not using a USBASP AVR programmer. Run
`avrudude -c ?` to get the list of programmer names.

Then run

    # make flash

To flash the program memory, eeprom, and fuses, or

    # make flash-program

to flash just the program memory, or

    # make flash-eeprom

to flash just the EEPROM

Usage
-----

See `doc/usage.md` for an explanation of how to use the modes and special
functions.

Configuration
-------------

See `eep_core.S` and `eeprom.S` for the configuration values that are stored in
EEPROM. These values are possible to change at run-time by using the
eeprom_write special function. You can also just change `eep_core.S` or
`eeprom.S` and flash your changes by running `make flash-eeprom`.

Some configuration values were considered not worth making reconfigurable in
EEPROM or do not make sense to make reconfigurable in EEPROM (eg pin
connections). These are just `#defined` near the top of `main.S`.

Hacking
-------

See `doc/hacking.txt` for some background and information on the theory of
operation. See `doc/TODO.txt` for a list of some features and improvements that
I think could be useful (or at least amusing) to implement.

Bugs
----

Please send any bugs, suggestions, questions, comments, etc to
snth@snthhacks.com

Learning AVR assembly
---------------------

In addition to the part datasheet and the AVR Instruction Set Manual, these are
some resources I found helpful in learning to program AVRs in assembly:

 - <http://www.elektronik-labor.de/AVR/KursAssembler/T13asm13.html>
   - A cute tutorial which also includes a brief introduction to the actual
     machine code and the SPI programming protocol.
   - In German, but I found the Google Translate English translation mostly
     usable.
     - Sometimes the opcodes and stuff in the assembly source get translated, so
       one may want to cross-reference the untranslated version's program
       listings.
   - Does not use GNU as / avr-gcc, so you will want to reference the GNU as
     manual: <https://sourceware.org/binutils/docs/as/> (or `info as`).
     - In particular, the AVR Dependent Features section:
       <https://sourceware.org/binutils/docs/as/AVR_002dDependent.html#AVR_002dDependent>
 - <http://www.nongnu.org/avr-libc/user-manual/assembler.html>
   - Example of how to use avr-gcc and avr-libc for assembly.
