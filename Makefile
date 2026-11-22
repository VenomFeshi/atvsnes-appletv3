CORE_URL := https://github.com/libretro/snes9x2005.git
CORE_REV := a79dfe9047e7fec58808aefe48ad2bf499c7af11
CORE := $(abspath build/snes9x2005)
CORE_READY := $(CORE)/.git/atvsnes-ready
LIBRETRO := $(CORE)/libretro-common/include

TOOLCHAIN ?= $(abspath ../toolchain)
SDK ?= $(TOOLCHAIN)/iPhoneOS8.4.sdk
LD64 ?= $(TOOLCHAIN)/bin/ld64-242
CLANG ?= xcrun clang

IOS_FLAGS = -target armv7-apple-ios8.0 -isysroot "$(SDK)"
LINK_FLAGS = $(IOS_FLAGS) -mlinker-version=242 --ld-path="$(LD64)"
FRONTEND_FLAGS = -std=gnu99 -Os -Wall -Wextra -I"$(LIBRETRO)" -DATVSNES_CORE_REV='"$(CORE_REV)"'
FRAMEWORKS = -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework AudioToolbox
BLE_FRAMEWORKS = -framework Foundation -framework QuartzCore -framework CoreBluetooth
CORE_FRONTEND := src/core_smoke.c src/game.c
HEADERS := $(wildcard src/*.h)
ATV_OBJS := $(addprefix build/atv/,$(addsuffix .o,appliance ble_bridge ble_client catalog menu pause_menu playback idle audio game state_store))
BUNDLE := build/ATVSNES.frappliance
ATV_CORE := $(CORE)/atvsnes-core.a
HOST_CORE := $(abspath build/host-core/atvsnes-host-core.a)

.PHONY: all check-ios host-test
all: $(BUNDLE)/ATVSNES $(BUNDLE)/TopRowIcon.png build/atv-core-smoke build/atvsnes-bluetooth

$(CORE_READY):
	mkdir -p build
	git clone --no-checkout "$(CORE_URL)" "$(CORE)"
	git -C "$(CORE)" checkout --detach "$(CORE_REV)"
	touch "$@"

check-ios:
	@test -d "$(SDK)/usr/include" || { echo "Set SDK to the iPhoneOS8.4.sdk directory." >&2; exit 1; }
	@test -x "$(LD64)" || { echo "Set LD64 to the ld executable from Xcode 6.4." >&2; exit 1; }

$(ATV_CORE): $(CORE_READY) | check-ios
	$(MAKE) -C "$(CORE)" platform=ios9 IOSSDK="$(SDK)" STATIC_LINKING=1 TARGET="$(notdir $@)"

build/atv/%.o: src/%.c $(HEADERS) $(CORE_READY) Makefile | check-ios
	mkdir -p build/atv
	$(CLANG) $(IOS_FLAGS) $(FRONTEND_FLAGS) -c "$<" -o "$@"

build/atv/%.o: src/%.m $(HEADERS) $(CORE_READY) Makefile | check-ios
	mkdir -p build/atv
	$(CLANG) $(IOS_FLAGS) $(FRONTEND_FLAGS) -fobjc-arc -c "$<" -o "$@"

$(BUNDLE)/ATVSNES: $(ATV_OBJS) src/Info.plist $(ATV_CORE) Makefile | check-ios
	mkdir -p "$(BUNDLE)"
	$(CLANG) $(LINK_FLAGS) -bundle $(ATV_OBJS) "$(ATV_CORE)" $(FRAMEWORKS) -o "$@"
	cp src/Info.plist "$(BUNDLE)/Info.plist"
	cp "$(CORE)/copyright" "$(BUNDLE)/Snes9x-copyright.txt"

$(BUNDLE)/TopRowIcon.png: scripts/make-icon.py
	mkdir -p "$(BUNDLE)"
	python3 scripts/make-icon.py "$@"

build/atv-core-smoke: src/main.c $(CORE_FRONTEND) $(HEADERS) $(ATV_CORE) Makefile | check-ios
	$(CLANG) $(LINK_FLAGS) $(FRONTEND_FLAGS) src/main.c $(CORE_FRONTEND) "$(ATV_CORE)" -o "$@"

# Separate source trees keep armv7 and Mac object files out of each other's builds.
$(HOST_CORE): $(CORE_READY)
	mkdir -p build/host-core
	git -C "$(CORE)" archive "$(CORE_REV)" | tar -x -C build/host-core
	GIT_DIR="$(CORE)/.git" $(MAKE) -C build/host-core platform=osx STATIC_LINKING=1 \
	    TARGET="$(notdir $@)" ARCHFLAGS="-arch $$(uname -m)"

build/host-core-smoke: src/main.c $(CORE_FRONTEND) $(HEADERS) $(HOST_CORE) Makefile
	$(CLANG) $(FRONTEND_FLAGS) src/main.c $(CORE_FRONTEND) "$(HOST_CORE)" -o "$@"

build/host-catalog-test: tests/catalog_test.m src/catalog.m src/catalog.h Makefile
	mkdir -p build
	$(CLANG) -fobjc-arc -Wall -Wextra -Isrc -framework Foundation tests/catalog_test.m src/catalog.m -o "$@"

build/atv-catalog-test: tests/catalog_test.m src/catalog.m src/catalog.h Makefile | check-ios
	mkdir -p build
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c tests/catalog_test.m -o build/atv-catalog-test.o
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c src/catalog.m -o build/atv-catalog.o
	$(CLANG) $(LINK_FLAGS) -framework Foundation build/atv-catalog-test.o build/atv-catalog.o -o "$@"

build/atv-bluetooth-probe: tests/bluetooth_probe.m src/ble_protocol.h Makefile | check-ios
	mkdir -p build
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -c tests/bluetooth_probe.m -o build/atv-bluetooth-probe.o
	$(CLANG) $(LINK_FLAGS) -framework Foundation -framework CoreBluetooth build/atv-bluetooth-probe.o -o "$@"

build/atv-idle-test: tests/idle_test.m build/atv/idle.o Makefile | check-ios
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c tests/idle_test.m -o build/atv-idle-test.o
	$(CLANG) $(LINK_FLAGS) -framework Foundation build/atv-idle-test.o build/atv/idle.o -o "$@"

build/atv-pause-test: tests/playback_pause_test.m build/atv/pause_menu.o build/atv/playback.o build/atv/idle.o build/atv/audio.o build/atv/game.o $(ATV_CORE) $(HEADERS) Makefile | check-ios
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c tests/playback_pause_test.m -o build/atv-pause-test.o
	$(CLANG) $(LINK_FLAGS) $(FRAMEWORKS) build/atv-pause-test.o $(filter %.o %.a,$^) -o "$@"

build/atv-state-test: tests/playback_state_test.m build/atv/state_store.o build/atv/playback.o build/atv/idle.o build/atv/audio.o build/atv/game.o $(ATV_CORE) $(HEADERS) Makefile | check-ios
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c tests/playback_state_test.m -o build/atv-state-test.o
	$(CLANG) $(LINK_FLAGS) $(FRAMEWORKS) build/atv-state-test.o $(filter %.o %.a,$^) -o "$@"

build/atvsnes-bluetooth: build/atv/ble_helper.o build/atv/ble_bridge.o build/atv/bluetooth.o Makefile | check-ios
	$(CLANG) $(LINK_FLAGS) $(BLE_FRAMEWORKS) $(filter %.o,$^) -o "$@"

build/atv-controller-link-test: tests/controller_link_test.m build/atv/bluetooth.o build/atv/ble_bridge.o build/atv/ble_client.o Makefile | check-ios
	$(CLANG) $(IOS_FLAGS) -fobjc-arc -Wall -Wextra -Isrc -c tests/controller_link_test.m -o build/atv-controller-link-test.o
	$(CLANG) $(LINK_FLAGS) $(BLE_FRAMEWORKS) build/atv-controller-link-test.o $(filter %.o,$^) -o "$@"

build/host-ble-protocol-test: tests/ble_protocol_test.c src/ble_protocol.h Makefile
	mkdir -p build
	$(CLANG) -std=c99 -Wall -Wextra -Isrc tests/ble_protocol_test.c -o "$@"

build/host-ble-bridge-test: tests/ble_bridge_test.m src/ble_bridge.m src/ble_bridge.h Makefile
	mkdir -p build
	$(CLANG) -fobjc-arc -Wall -Wextra -Isrc -framework Foundation tests/ble_bridge_test.m src/ble_bridge.m -o "$@"

build/host-ble-slots-test: tests/ble_slots_test.m src/bluetooth.m $(HEADERS) Makefile
	mkdir -p build
	$(CLANG) -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations -Isrc $(BLE_FRAMEWORKS) \
	    tests/ble_slots_test.m src/bluetooth.m -o "$@"

build/host-display-test: tests/display_test.c src/display.h Makefile
	mkdir -p build
	$(CLANG) -std=c99 -Wall -Wextra -Isrc -framework CoreGraphics tests/display_test.c -o "$@"

build/host-state-store-test: tests/state_store_test.m src/state_store.m src/state_store.h Makefile
	mkdir -p build
	$(CLANG) $(FRONTEND_FLAGS) -fobjc-arc -Isrc -framework Foundation tests/state_store_test.m src/state_store.m -o "$@"

host-test: build/host-core-smoke build/host-catalog-test build/host-ble-protocol-test build/host-ble-bridge-test build/host-ble-slots-test build/host-display-test build/host-state-store-test
	./build/host-core-smoke
	./build/host-catalog-test
	./build/host-ble-protocol-test
	./build/host-ble-bridge-test
	./build/host-ble-slots-test
	./build/host-display-test
	./build/host-state-store-test
