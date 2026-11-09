THEOS ?= $(error set THEOS to the Theos directory)
TC ?= $(THEOS)/toolchain/linux/iphone/bin
CG_SDK_V7 ?= $(error set CG_SDK_V7 to the armv7 SDK)
CG_SDK_V64 ?= $(error set CG_SDK_V64 to the arm64 SDK)
CG_CRT_V7 ?= $(CG_SDK_V7)/usr/lib/crt1.o
BUILD ?= build
VERSION := $(shell awk '/^Version:/ { print $$2; exit }' control)
CC := $(TC)/clang
PYTHON ?= python3
SOURCES := $(wildcard src/*.m) $(wildcard src/*.c)
OBJECTS_V7 := $(addprefix $(BUILD)/armv7/,$(addsuffix .o,$(SOURCES)))
OBJECTS_V64 := $(addprefix $(BUILD)/arm64/,$(addsuffix .o,$(SOURCES)))
FRAMEWORKS := -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework OpenGLES -framework OpenAL -framework AVFoundation
CFLAGS := -Wall -O2 -Isrc -fblocks

.PHONY: all test test-assets deb ipa clean
all: $(BUILD)/ChickenGun

$(BUILD)/armv7/%.m.o: %.m
	@mkdir -p $(@D)
	$(CC) -target arm-apple-darwin11 -B $(TC) -arch armv7 -miphoneos-version-min=6.0 -isysroot $(CG_SDK_V7) $(CFLAGS) -fobjc-arc -c $< -o $@

$(BUILD)/armv7/%.c.o: %.c
	@mkdir -p $(@D)
	$(CC) -target arm-apple-darwin11 -B $(TC) -arch armv7 -miphoneos-version-min=6.0 -isysroot $(CG_SDK_V7) $(CFLAGS) -c $< -o $@

$(BUILD)/arm64/%.m.o: %.m
	@mkdir -p $(@D)
	$(CC) -target arm64-apple-darwin -B $(TC) -arch arm64 -miphoneos-version-min=7.0 -isysroot $(CG_SDK_V64) $(CFLAGS) -fobjc-arc -c $< -o $@

$(BUILD)/arm64/%.c.o: %.c
	@mkdir -p $(@D)
	$(CC) -target arm64-apple-darwin -B $(TC) -arch arm64 -miphoneos-version-min=7.0 -isysroot $(CG_SDK_V64) $(CFLAGS) -c $< -o $@

$(BUILD)/armv7/ChickenGun: $(OBJECTS_V7)
	$(CC) -target arm-apple-darwin11 -B $(TC) -arch armv7 -miphoneos-version-min=6.0 -isysroot $(CG_SDK_V7) -nostartfiles $(CG_CRT_V7) $^ $(FRAMEWORKS) -o $@

$(BUILD)/arm64/ChickenGun: $(OBJECTS_V64)
	$(CC) -target arm64-apple-darwin -B $(TC) -arch arm64 -miphoneos-version-min=7.0 -isysroot $(CG_SDK_V64) $^ $(FRAMEWORKS) -weak_framework AVFAudio -o $@

$(BUILD)/ChickenGun: $(BUILD)/armv7/ChickenGun $(BUILD)/arm64/ChickenGun
	$(TC)/lipo -create $^ -output $@
	$(TC)/ldid -S $@

test:
	DUMP_ASSETS="$${DUMP_ASSETS:-}" sh tools/tests/run_all.sh

test-assets:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) tools/tests/outfit_check.py

deb: $(BUILD)/ChickenGun
	rm -rf $(BUILD)/stage
	mkdir -p $(BUILD)/stage/DEBIAN $(BUILD)/stage/Applications/ChickenGun.app
	cp control $(BUILD)/stage/DEBIAN/control
	cp -R Resources/. $(BUILD)/stage/Applications/ChickenGun.app/
	cp $(BUILD)/ChickenGun $(BUILD)/stage/Applications/ChickenGun.app/ChickenGun
	chmod 755 $(BUILD)/stage/Applications/ChickenGun.app/ChickenGun
	dpkg-deb --root-owner-group -Zgzip --build $(BUILD)/stage $(BUILD)/cg-retro-$(VERSION).deb

ipa: $(BUILD)/ChickenGun
	rm -rf $(BUILD)/ipa-stage
	mkdir -p $(BUILD)/ipa-stage/Payload/ChickenGun.app
	cp -R Resources/. $(BUILD)/ipa-stage/Payload/ChickenGun.app/
	cp $(BUILD)/ChickenGun $(BUILD)/ipa-stage/Payload/ChickenGun.app/ChickenGun
	chmod 755 $(BUILD)/ipa-stage/Payload/ChickenGun.app/ChickenGun
	rm -f $(BUILD)/cg-retro-$(VERSION).ipa
	cd $(BUILD)/ipa-stage && zip -qr "$(abspath $(BUILD))/cg-retro-$(VERSION).ipa" Payload
	unzip -tq $(BUILD)/cg-retro-$(VERSION).ipa

clean:
	rm -rf $(BUILD)
