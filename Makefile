# Commands for the VdvLive app.
#
# DEVELOPER_DIR is set explicitly so the build works even when xcode-select
# points at the Command Line Tools instead of Xcode.

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := VdvLive.xcodeproj
SCHEME := VdvLive
CONFIGURATION ?= Debug
DERIVED_DATA := build

# Pick another simulator with: make run SIMULATOR="iPhone 16 Pro"
SIMULATOR ?= iPhone 17
APP_ID := cz.ondralinek.VdvLive

# The watch app, and the watch simulator 'make watchrun' puts it in. The watch app
# is a target of its own, but it reaches a real watch inside the phone app: see
# 'make deploy'.
WATCH_SIMULATOR ?= VDV Watch
WATCH_ID := cz.ondralinek.VdvLive.watchkitapp
WATCH_DEVICE_TYPE ?= com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm
WATCH_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.watchOS-27-0
WATCH_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-watchsimulator/VdvLive Watch.app
# Extra launch arguments for 'make watchrun', e.g. WATCH_ARGS=-watchDelayBands.
WATCH_ARGS ?=
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/VdvLive.app
DEVICE_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/VdvLive.app
SIMULATOR_APP := $(DEVELOPER_DIR)/Applications/Simulator.app

# Which iPhone to install on, as a UDID. Empty means "the only one plugged in".
DEVICE ?=
# Signing team. Empty means "whatever Xcode has configured".
TEAM ?=
# A physical iPhone reports a 25 character UDID; a simulator reports a 36
# character UUID, which does not match this pattern.
DEVICE_PATTERN := [0-9A-F]{8}-[0-9A-F]{16}

# Shell snippet that resolves the target iPhone into $$udid: DEVICE= when it is
# given, otherwise the only physical device plugged into this Mac.
RESOLVE_DEVICE = udid='$(DEVICE)'; \
	if [ -z "$$udid" ]; then \
		udid=$$(xcrun devicectl list devices 2>/dev/null | grep -v simulated | grep -oE '$(DEVICE_PATTERN)' | head -1); \
	fi;

# A free Apple ID signs with a certificate iOS does not know, so the very first
# launch is refused until the developer is trusted on the device by hand.
TRUST_NOTE = echo ""; \
	echo "note: iOS has not been told to trust this developer yet. Do it once on the"; \
	echo "      device: Settings > General > VPN & Device Management >"; \
	echo "      Developer App > the Apple ID > Trust. Then run 'make launch'."; \
	echo "      Nothing needs rebuilding.";

# iOS refuses to open any app while the screen is locked, which is not a problem
# with the build at all.
LOCKED_NOTE = echo "note: the iPhone is locked. Unlock it and run 'make launch' again.";

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

# The watch app is a second scheme in the same project, so it needs a base command
# of its own: `xcodebuild` refuses to be told a scheme twice.
WATCH_XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED_DATA)

# Fast type check without xcodebuild: the compiler is called directly, which
# also works before the Xcode licence agreement has been accepted.
SWIFTC := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
IOS_SIMULATOR_PLATFORM := $(DEVELOPER_DIR)/Platforms/iPhoneSimulator.platform/Developer
IOS_SIMULATOR_SDK := $(IOS_SIMULATOR_PLATFORM)/SDKs/iPhoneSimulator.sdk
SWIFT_TARGET ?= arm64-apple-ios18.0-simulator
TYPECHECK_DIR := $(DERIVED_DATA)/typecheck
LIVE_DIR := $(DERIVED_DATA)/live
# Width the mirrored frames are downscaled to before they reach the browser.
LIVE_WIDTH ?= 720
APP_SOURCES := $(shell find VdvLive -name '*.swift' | sort)
TEST_SOURCES := $(shell find VdvLiveTests -name '*.swift' | sort)

# Where the national timetable archive comes from, for 'make mapping'.
ARCHIVE_URL := https://portal.cisjr.cz/pub/JDF/JDF.zip

.PHONY: all build test typecheck run deploy launch iphones screenshot live icon mapping devices open clean help

all: build

## Build the app for the simulator.
build:
	$(XCODEBUILD) -configuration $(CONFIGURATION) -destination 'generic/platform=iOS Simulator' build

## Run the unit tests on $(SIMULATOR).
test:
	$(XCODEBUILD) -configuration Debug -destination 'platform=iOS Simulator,name=$(SIMULATOR)' test

## Type check the app and test sources without building or signing anything.
typecheck:
	@mkdir -p $(TYPECHECK_DIR)
	$(SWIFTC) -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -D DEBUG -enable-testing -module-name VdvLive -emit-module -emit-module-path $(TYPECHECK_DIR)/VdvLive.swiftmodule $(APP_SOURCES)
	$(SWIFTC) -typecheck -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -D DEBUG $(APP_SOURCES)
	$(SWIFTC) -typecheck -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -enable-testing -module-name VdvLiveTests -I $(TYPECHECK_DIR) -I '$(IOS_SIMULATOR_PLATFORM)/usr/lib' -F '$(IOS_SIMULATOR_PLATFORM)/Library/Frameworks' $(TEST_SOURCES)
	@echo "type check passed"

## Build, install and launch the app on the booted simulator.
run: build
	-xcrun simctl boot '$(SIMULATOR)'
	@if [ -d '$(SIMULATOR_APP)' ]; then open '$(SIMULATOR_APP)'; else echo "note: $(SIMULATOR_APP) is missing, the simulator runs headless - use 'make screenshot'"; fi
	xcrun simctl bootstatus '$(SIMULATOR)' -b
	xcrun simctl install '$(SIMULATOR)' '$(APP_BUNDLE)'
	xcrun simctl launch '$(SIMULATOR)' $(APP_ID)

## Build for a physical iPhone, install the app there and launch it.
##
## The device defaults to the only iPhone plugged into this Mac; pass
## DEVICE=<udid> when several are (see 'make iphones'). Signing needs an Apple ID
## with a team chosen for this target in Xcode, plus Developer Mode on the phone.
## An Apple ID the phone has not been told to trust needs one confirmation on the
## device, which this prints when it happens. See the README for the details.
deploy:
	@$(RESOLVE_DEVICE) \
	if [ -z "$$udid" ]; then \
		echo "error: no iPhone is plugged in - connect one over USB, or pass DEVICE=<udid>"; \
		exit 1; \
	fi; \
	echo "deploying to $$udid"; \
	$(XCODEBUILD) -configuration $(CONFIGURATION) -destination "platform=iOS,id=$$udid" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		$(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM)) build && \
	xcrun devicectl device install app --device "$$udid" '$(DEVICE_APP)'
	@$(MAKE) --no-print-directory launch

## Launch the app on the iPhone without rebuilding or reinstalling it.
launch:
	@$(RESOLVE_DEVICE) \
	output=$$(xcrun devicectl device process launch --device "$$udid" $(APP_ID) 2>&1); \
	returned=$$?; \
	if [ $$returned -eq 0 ]; then \
		echo "launched $(APP_ID) on $$udid"; \
		exit 0; \
	fi; \
	case "$$output" in \
		*"not be, unlocked"*) $(LOCKED_NOTE) ;; \
		*"trusted"*) $(TRUST_NOTE) ;; \
		*) echo "$$output" ;; \
	esac; \
	exit 1

## List the iPhones plugged into this Mac. Simulators are listed by 'make devices'.
iphones:
	@xcrun devicectl list devices 2>/dev/null | grep -v simulated

## Save a screenshot of the running app from the booted simulator.
screenshot:
	xcrun simctl io '$(SIMULATOR)' screenshot $(DERIVED_DATA)/screenshot.png
	@echo "wrote $(DERIVED_DATA)/screenshot.png"

## Build the watch app on its own. A real watch gets it through the phone app,
## which carries it in its Watch folder.
watch:
	$(WATCH_XCODEBUILD) -configuration $(CONFIGURATION) -scheme VdvLiveWatch \
		-destination 'generic/platform=watchOS Simulator' build

## Run the watch app in a watch simulator, creating it if it is not there yet.
## Pin lines first: the watch shows only what the phone sends it, so with nothing
## pinned the map is empty on purpose. Seeded lines can be set with, for example:
##   xcrun simctl spawn '$(WATCH_SIMULATOR)' defaults write $(WATCH_ID) \
##       favouriteLines -array 358300 764330
watchrun: watch
	@xcrun simctl list devices available | grep -q '$(WATCH_SIMULATOR) (' || \
		xcrun simctl create '$(WATCH_SIMULATOR)' $(WATCH_DEVICE_TYPE) $(WATCH_RUNTIME)
	@xcrun simctl boot '$(WATCH_SIMULATOR)' 2>/dev/null || true
	@xcrun simctl bootstatus '$(WATCH_SIMULATOR)' -b >/dev/null 2>&1 || true
	xcrun simctl install '$(WATCH_SIMULATOR)' '$(WATCH_APP)'
	-xcrun simctl terminate '$(WATCH_SIMULATOR)' $(WATCH_ID) 2>/dev/null
	xcrun simctl launch '$(WATCH_SIMULATOR)' $(WATCH_ID) $(WATCH_ARGS)

## Save a screenshot of the watch simulator.
watchshot:
	xcrun simctl io '$(WATCH_SIMULATOR)' screenshot $(DERIVED_DATA)/watch.png
	@echo "wrote $(DERIVED_DATA)/watch.png"

## List the watch simulators available for WATCH_SIMULATOR=....
watches:
	@xcrun simctl list devices available | awk '/-- watchOS/{found=1; next} /^--/{found=0} found'

## Mirror the booted simulator into a browser tab at 1 fps. Ctrl-C stops it.
##
## Workaround for Xcode installs without Contents/Developer/Applications/Simulator.app:
## it is a read-only view, taps have to go through Xcode or a device build.
## Frames are re-encoded to JPEG at LIVE_WIDTH: a full resolution PNG is around
## 2 MB, which is a lot of disk to rewrite every second.
live:
	@mkdir -p $(LIVE_DIR)
	@cp tools/live-view.html $(LIVE_DIR)/index.html
	@open $(LIVE_DIR)/index.html
	@echo "mirroring $(SIMULATOR) to $(LIVE_DIR)/live.jpg once a second - press Ctrl-C to stop"
	@while true; do \
		xcrun simctl io '$(SIMULATOR)' screenshot --type=png $(LIVE_DIR)/.frame.png >/dev/null 2>&1; \
		sips -s format jpeg -Z $(LIVE_WIDTH) $(LIVE_DIR)/.frame.png --out $(LIVE_DIR)/.live.jpg >/dev/null 2>&1; \
		mv -f $(LIVE_DIR)/.live.jpg $(LIVE_DIR)/live.jpg 2>/dev/null; \
		rm -f $(LIVE_DIR)/.frame.png; \
		sleep 1; \
	done

## Regenerate the app icons, the phone app's and the watch app's, from one script so
## the two cannot drift apart. The map behind the bus is the region's own roads and
## rivers, which come from OpenStreetMap: the first run fetches them and caches them
## under build/, so later runs are offline. Delete $(REGION_MAP) to refresh the map.
REGION_MAP := build/icon/region-map.json
icon: $(REGION_MAP)
	swift tools/generate-app-icon.swift

$(REGION_MAP):
	@mkdir -p $(dir $@)
	python3 tools/fetch-region-map.py "$@"

## Refresh the shipped line to entry mapping. The archive it is read from is
## republished a few times a week and reassigns its entry names, which leaves the
## mapping pointing at entries that hold other lines. Commit the result.
ARCHIVE ?= /tmp/jdf/JDF.zip
mapping:
	@mkdir -p $(dir $(ARCHIVE))
	@[ -f "$(ARCHIVE)" ] || curl -sS -L -o "$(ARCHIVE)" $(ARCHIVE_URL)
	python3 tools/jdf_lines_mapping.py "$(ARCHIVE)" VdvLive/Resources/jdf-lines.json

## Refresh the shipped stop positions. No timetable source carries coordinates, so they
## are matched from OpenStreetMap by stop name, and what a name cannot settle is placed by
## rule or left for review; see docs/stops.md and .github/skills/stop-positions/SKILL.md.
## Commit the bundle and docs/stop-review.md. Stages 1 and 2 are cached under build/stops/.
stops:
	@mkdir -p $(dir $(ARCHIVE))
	@[ -f "$(ARCHIVE)" ] || curl -sS -L -o "$(ARCHIVE)" $(ARCHIVE_URL)
	JDF_ARCHIVE="$(ARCHIVE)" .github/skills/stop-positions/scripts/run_all.sh

## List the simulators available for SIMULATOR=....
devices:
	@xcrun simctl list devices available | awk '/-- iOS/{found=1; next} /^--/{found=0} found'

## Open the project in Xcode.
open:
	open $(PROJECT)

clean:
	$(XCODEBUILD) clean
	rm -rf $(DERIVED_DATA)

## Show this help.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
