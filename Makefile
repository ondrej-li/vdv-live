# Commands for the VdvMap app.
#
# DEVELOPER_DIR is set explicitly so the build works even when xcode-select
# points at the Command Line Tools instead of Xcode.

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := VdvMap.xcodeproj
SCHEME := VdvMap
CONFIGURATION ?= Debug
DERIVED_DATA := build

# Pick another simulator with: make run SIMULATOR="iPhone 16 Pro"
SIMULATOR ?= iPhone 17
APP_ID := cz.ondralinek.VdvMap
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/VdvMap.app
DEVICE_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/VdvMap.app
SIMULATOR_APP := $(DEVELOPER_DIR)/Applications/Simulator.app

# Which iPhone to install on, as a UDID. Empty means "the only one plugged in".
DEVICE ?=
# Signing team. Empty means "whatever Xcode has configured".
TEAM ?=
# A physical iPhone reports a 25 character UDID; a simulator reports a 36
# character UUID, which does not match this pattern.
DEVICE_PATTERN := [0-9A-F]{8}-[0-9A-F]{16}

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA)

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
APP_SOURCES := $(shell find VdvMap -name '*.swift' | sort)
TEST_SOURCES := $(shell find VdvMapTests -name '*.swift' | sort)

.PHONY: all build test typecheck run deploy iphones screenshot live icon devices open clean help

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
	$(SWIFTC) -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -D DEBUG -enable-testing -module-name VdvMap -emit-module -emit-module-path $(TYPECHECK_DIR)/VdvMap.swiftmodule $(APP_SOURCES)
	$(SWIFTC) -typecheck -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -D DEBUG $(APP_SOURCES)
	$(SWIFTC) -typecheck -sdk '$(IOS_SIMULATOR_SDK)' -target $(SWIFT_TARGET) -swift-version 5 -enable-testing -module-name VdvMapTests -I $(TYPECHECK_DIR) -I '$(IOS_SIMULATOR_PLATFORM)/usr/lib' -F '$(IOS_SIMULATOR_PLATFORM)/Library/Frameworks' $(TEST_SOURCES)
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
## in Xcode > Settings > Accounts, and the iPhone needs Developer Mode switched
## on under Settings > Privacy & Security. See the README for the details.
deploy:
	@udid='$(DEVICE)'; \
	if [ -z "$$udid" ]; then \
		udid=$$(xcrun devicectl list devices 2>/dev/null | grep -v simulated | grep -oE '$(DEVICE_PATTERN)' | head -1); \
	fi; \
	if [ -z "$$udid" ]; then \
		echo "error: no iPhone is plugged in - connect one over USB, or pass DEVICE=<udid>"; \
		exit 1; \
	fi; \
	echo "deploying to $$udid"; \
	$(XCODEBUILD) -configuration $(CONFIGURATION) -destination "platform=iOS,id=$$udid" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration \
		$(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM)) build && \
	xcrun devicectl device install app --device "$$udid" '$(DEVICE_APP)' && \
	xcrun devicectl device process launch --device "$$udid" $(APP_ID)

## List the iPhones plugged into this Mac. Simulators are listed by 'make devices'.
iphones:
	@xcrun devicectl list devices 2>/dev/null | grep -v simulated

## Save a screenshot of the running app from the booted simulator.
screenshot:
	xcrun simctl io '$(SIMULATOR)' screenshot $(DERIVED_DATA)/screenshot.png
	@echo "wrote $(DERIVED_DATA)/screenshot.png"

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

## Regenerate the app icon PNG (only needed when the icon design changes).
icon:
	swift tools/generate-app-icon.swift

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
