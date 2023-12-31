CC := avr-gcc
OBJCOPY := avr-objcopy

MCU ?= attiny13a
AVRDUDE_MCU ?= t13
F_CPU ?= 4800000
# Cheap SPI programmer. Override if using a different programmer.
PROGRAMMER ?= usbasp

CPPFLAGS ?= -DF_CPU=$(F_CPU)
CFLAGS ?= $(CPPFLAGS) -MMD -MP -O0 -mmcu=$(MCU)

LDFLAGS = -mmcu=$(MCU) -nostdlib

PRGOBJ ?= main.o
EEPOBJ ?= eeprom.o

OBJECTS ?= $(PRGOBJ) $(EEPOBJ)
dep_files := $(addsuffix .d, $(basename $(OBJECTS)))

_TARGET = binlight
TARGET ?= $(_TARGET).ihex

_EEPROM_TARGET = eeprom
EEPROM_TARGET ?= $(_EEPROM_TARGET).ihex

.PHONY: all
all: $(TARGET) $(EEPROM_TARGET)

$(TARGET): $(_TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(_TARGET).elf: $(PRGOBJ)
	$(CC) $(LDFLAGS) -o $@ $^

.PHONY: eeprom
eeprom: $(EEPROM_TARGET)

$(EEPROM_TARGET): $(EEPOBJ)
	$(OBJCOPY) -j .eeprom --change-section-lma .eeprom=0 -O ihex $< $@

$(OBJECTS): %.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<


.PHONY: flash
flash: flash-program flash-eeprom flash-fuse

.PHONY: flash-program
flash-program: $(TARGET)
	avrdude -c $(PROGRAMMER) -p $(AVRDUDE_MCU) -U flash:w:$(TARGET):i

.PHONY: flash-eeprom
flash-eeprom: $(EEPROM_TARGET)
	avrdude -c $(PROGRAMMER) -p $(AVRDUDE_MCU) -U eeprom:w:$<:i

# Set BODLEVEL[1:0] to '10' to set the Brown-Out Detection voltage (Vbot) to
# 1.8V (typ). I think enabling brown-out detection is useful because we do not
# corruption when writing to EEPROM. For example it could cause the unbrick
# feature to be incorrectly triggered.
HFUSE ?= 0xFD
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
	rm -f $(TARGET) $(_TARGET).elf
	rm -f $(EEPROM_TARGET)
	rm -f $(OBJECTS)
	rm -f $(dep_files)

-include $(dep_files)
