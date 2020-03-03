CC := avr-gcc
OBJCOPY := avr-objcopy

MCU ?= attiny13
AVRDUDE_MCU ?= t13
F_CPU ?= 
# Cheap SPI programmer. Override if using a different programmer.
PROGRAMMER ?= usbasp

CPPFLAGS ?= -DF_CPU=$(F_CPU)
CFLAGS ?= $(CPPFLAGS) -mmcu=$(MCU)

LDFLAGS = -mmcu=$(MCU) -nostdlib

OBJECTS ?= main.o

EEPOBJ ?= eeprom.o

_TARGET = snth-10dd
TARGET ?= $(_TARGET).ihex

_EEPROM_TARGET = eeprom
EEPROM_TARGET ?= $(_EEPROM_TARGET).ihex

.PHONY: all
all: $(TARGET) $(EEPROM_TARGET)

$(TARGET): $(_TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(_TARGET).elf: $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

.PHONY: eeprom
eeprom: $(EEPROM_TARGET)

$(EEPROM_TARGET): $(EEPOBJ)
	$(OBJCOPY) -j .eeprom --change-section-lma .eeprom=0 -O ihex $< $@

$(OBJECTS) $(EEPOBJ): %.o: %.S
	$(CC) $(CFLAGS) -O0 -c -o $@ $<


.PHONY: flash-all
flash-all: flash flash-eeprom flash-fuse

.PHONY: flash
flash: $(TARGET)
	avrdude -c $(PROGRAMMER) -p $(AVRDUDE_MCU) -U flash:w:$(TARGET):i

.PHONY: flash-eeprom
flash-eeprom: $(EEPROM_TARGET)
	avrdude -c $(PROGRAMMER) -p $(AVRDUDE_MCU) -U eeprom:w:$<:i

HFUSE ?= 0xFF
# Use 4.8MHz internal clock source; Startup delay of 14CK + 4ms "Fast rising
# power"; Preserve EEPROM through chip erase.
# To use The 9.6MHz clock source, change to 0x76.
# To change to 14CK + 64ms "Slow rising power" startup delay, change to 0x79.
# To not preserve EEPROM through chip erase, change to 0x75
# Remember to define F_CPU accordingly if changing the CPU frequency.
LFUSE ?= 0x35

.PHONY: flash-fuse
flash-fuse:
	avrdude -c $(PROGRAMMER) -p $(AVRDUDE_MCU) -U hfuse:w:$(HFUSE):m -U lfuse:w:$(LFUSE):m

.PHONY: clean
clean:
