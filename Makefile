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
# Signing team. Empty means "whatever Xcode has configured", which for a free
# Apple ID is a personal team that cannot sign anything for the App Store.
#
# Enrolling in the Apple Developer Program gives the account a team of its own, and
# its id is what every target here needs. Put it in `.team` (git-ignored, one line)
# rather than in the project: the project keeps the personal team `make deploy`
# needs for the phone on the desk, and `make archive TEAM=...` overrides it for the
# archive in one place.
TEAM ?= $(shell [ -f .team ] && tr -d '[:space:]' < .team)
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

# App Store: the archived build, the exported .ipa, and the export options written
# on the way (never committed: they carry the team).
ARCHIVE_PATH := $(DERIVED_DATA)/VdvLive.xcarchive
EXPORT_PATH := $(DERIVED_DATA)/export
EXPORT_OPTIONS := $(DERIVED_DATA)/ExportOptions.plist
# What App Store Connect calls the version, and the build number it compares every
# upload against. The build is stamped from the clock unless it is given, so an
# upload can never be refused for repeating the one before it.
VERSION ?= 1.0
BUILD ?= $(shell date +%y%m%d%H%M)

# Where 'make shots' puts the App Store screenshots, and the devices it takes them
# on: the two sizes Apple asks for, plus the watch.
APPSTORE_SHOTS := $(DERIVED_DATA)/appstore
SHOT_IPHONE ?= iPhone 18 Pro Max
SHOT_IPAD ?= iPad Pro 13-inch (M5)
SHOT_WATCH ?= Apple Watch Ultra 4 (49mm)
SHOT_DELAY ?= 12
# The viewport the screenshots are taken in: the region itself, tightly enough that
# the markers are readable. Seeded as the app's own saved map view, so the shot does
# not depend on what the camera happens to fit on a given screen.
SHOT_LATITUDE ?= 49.4
SHOT_LONGITUDE ?= 15.6
SHOT_LATITUDE_DELTA ?= 0.62
SHOT_LONGITUDE_DELTA ?= 0.95
# The watch's map takes longer to draw its first tiles than the phone's.
SHOT_WATCH_DELAY ?= 30

.PHONY: all build test typecheck run deploy launch iphones screenshot live icon mapping devices open clean help archive ipa upload check-release shots shots-watch

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

# --- The App Store ----------------------------------------------------------
#
# What a submission needs from this Mac, in the order it is needed:
#
#   make check-release     is the paid team here, and what will be uploaded
#   make archive           the .xcarchive, signed for distribution
#   make upload            ...and straight to App Store Connect
#   make shots             the screenshots App Store Connect asks for
#
# App Store Connect itself (the app record, privacy answers, price, the review
# notes) is not something a Makefile can do; docs/ship.md has that half.

# ExportOptions for one export: always `app-store-connect`, with the destination
# deciding whether the build stays on this Mac or goes to Apple. Written on the
# way rather than committed, because it carries the team.
define export-options
mkdir -p '$(dir $(EXPORT_OPTIONS))'; \
plutil -create xml1 '$(EXPORT_OPTIONS)'; \
plutil -insert method -string app-store-connect '$(EXPORT_OPTIONS)'; \
plutil -insert destination -string $(1) '$(EXPORT_OPTIONS)'; \
plutil -insert signingStyle -string automatic '$(EXPORT_OPTIONS)'; \
plutil -insert manageAppVersionAndBuildNumber -bool NO '$(EXPORT_OPTIONS)'; \
plutil -insert uploadSymbols -bool YES '$(EXPORT_OPTIONS)'; \
if [ -n '$(TEAM)' ]; then plutil -insert teamID -string '$(TEAM)' '$(EXPORT_OPTIONS)'; fi
endef

## Say what an upload would carry: the team, the version, the bundle ids, and
## which signing identities this Mac actually has.
check-release:
	@echo "team:     $(if $(TEAM),$(TEAM),NOT SET - put the paid Team ID in .team)"
	@echo "version:  $(VERSION) ($(BUILD))"
	@echo "bundles:  $(APP_ID), $(WATCH_ID)"
	@echo "team ids on this Mac:"
	@for f in "$(HOME)"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do \
		[ -f "$$f" ] && security cms -D -i "$$f" 2>/dev/null | plutil -extract TeamIdentifier.0 raw - 2>/dev/null; \
	done | sort -u | sed 's/^/  /'
	@echo "distribution identities:"
	@ids=$$(security find-identity -v -p codesigning | grep -i distribution); \
	if [ -n "$$ids" ]; then echo "$$ids" | sed 's/^/  /'; \
	else echo "  none - Xcode > Settings > Accounts > Manage Certificates > Apple Distribution"; fi

## Build the App Store archive: Release, for a device, stamped with
## $(VERSION)/$(BUILD). Add TEAM=... or a .team file for the paid team.
archive:
	@test -n '$(TEAM)' || \
		echo "note: TEAM is not set, so the project's team signs this. That is enough for a device build and not for an upload: put the paid Team ID in .team."
	$(XCODEBUILD) -configuration Release -destination 'generic/platform=iOS' \
		-archivePath '$(ARCHIVE_PATH)' \
		CURRENT_PROJECT_VERSION=$(BUILD) MARKETING_VERSION=$(VERSION) \
		$(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM)) \
		-allowProvisioningUpdates archive
	@echo "archived $(ARCHIVE_PATH)"

## Export the App Store build (.ipa) from the archive, without sending it anywhere.
ipa: archive
	@$(call export-options,export)
	xcodebuild -exportArchive -archivePath '$(ARCHIVE_PATH)' -exportPath '$(EXPORT_PATH)' \
		-exportOptionsPlist '$(EXPORT_OPTIONS)' -allowProvisioningUpdates
	@echo "wrote $(EXPORT_PATH)"

## Export the archive and upload it to App Store Connect, where it lands in
## TestFlight first. Needs the Apple ID signed into Xcode.
upload: archive
	@$(call export-options,upload)
	xcodebuild -exportArchive -archivePath '$(ARCHIVE_PATH)' -exportPath '$(EXPORT_PATH)' \
		-exportOptionsPlist '$(EXPORT_OPTIONS)' -allowProvisioningUpdates
	@echo "uploaded $(VERSION) ($(BUILD)) - see App Store Connect > TestFlight"

# Screenshot one simulator: reboot it (a stale permission alert outlives the app
# that raised it, and survives being answered for another launch), install the app
# into a clean container whose settings say not to open on the position, let the
# feed answer, capture. The status bar is overridden the way Apple's own
# screenshots do it, so the shots carry neither the time of day nor a half-empty
# battery.
define capture-shot
@echo "capturing $(1) -> $(2)"; \
xcrun simctl shutdown '$(1)' >/dev/null 2>&1 || true; \
xcrun simctl boot '$(1)' >/dev/null 2>&1 || true; \
xcrun simctl bootstatus '$(1)' -b >/dev/null 2>&1 || true; \
xcrun simctl status_bar '$(1)' override --time '9:41' --dataNetwork wifi --wifiBars 3 \
	--cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true; \
xcrun simctl terminate '$(1)' $(APP_ID) >/dev/null 2>&1 || true; \
xcrun simctl uninstall '$(1)' $(APP_ID) >/dev/null 2>&1 || true; \
xcrun simctl install '$(1)' '$(APP_BUNDLE)'; \
container=$$(xcrun simctl get_app_container '$(1)' $(APP_ID) data); \
mkdir -p "$$container/Library/Preferences"; \
plutil -create xml1 "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert startsAtCurrentLocation -bool NO "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert showsCurrentLocation -bool NO "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView -dictionary "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.latitude -float $(SHOT_LATITUDE) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.longitude -float $(SHOT_LONGITUDE) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.latitudeDelta -float $(SHOT_LATITUDE_DELTA) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.longitudeDelta -float $(SHOT_LONGITUDE_DELTA) "$$container/Library/Preferences/$(APP_ID).plist"; \
xcrun simctl launch '$(1)' $(APP_ID) >/dev/null; \
sleep $(SHOT_DELAY); \
xcrun simctl io '$(1)' screenshot '$(APPSTORE_SHOTS)/$(2).png'
endef

## Capture the App Store screenshots at the two sizes Apple asks for: the largest
## iPhone and the 13-inch iPad. Override the devices with SHOT_IPHONE=/SHOT_IPAD=.
shots: build
	@mkdir -p '$(APPSTORE_SHOTS)'
	$(call capture-shot,$(SHOT_IPHONE),iphone-6.9)
	$(call capture-shot,$(SHOT_IPAD),ipad-13)
	@echo "wrote $(APPSTORE_SHOTS) - upload them under App Store Connect > Screenshots"

## Capture the watch screenshot too. The watch draws the pinned lines only, and it
## cannot read them from the phone on a Mac, so two are seeded first.
shots-watch: watch
	@mkdir -p '$(APPSTORE_SHOTS)'
	@xcrun simctl boot '$(SHOT_WATCH)' 2>/dev/null || true
	@xcrun simctl bootstatus '$(SHOT_WATCH)' -b >/dev/null 2>&1 || true
	@xcrun simctl spawn '$(SHOT_WATCH)' defaults write $(WATCH_ID) favouriteLines \
		-array 358300 764330
	xcrun simctl install '$(SHOT_WATCH)' '$(WATCH_APP)'
	-@xcrun simctl terminate '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null 2>&1
	xcrun simctl launch '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null
	@sleep $(SHOT_WATCH_DELAY)
	xcrun simctl io '$(SHOT_WATCH)' screenshot '$(APPSTORE_SHOTS)/watch-49mm.png'
	@echo "wrote $(APPSTORE_SHOTS)/watch-49mm.png"

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
