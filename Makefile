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
SWIFT_TARGET ?= arm64-apple-ios26.0-simulator
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
#
# Expanded once, not at every use: `?=` would re-read the clock each time it is
# mentioned, so the number printed at the end of an upload could differ from the one
# inside the archive - and the printed one is what a person carries to App Store
# Connect.
VERSION ?= 1.1
BUILD := $(if $(BUILD),$(BUILD),$(shell date +%y%m%d%H%M))

# Where 'make shots' puts the App Store screenshots, and the devices it takes them
# on: the two sizes Apple asks for, plus the watch.
APPSTORE_SHOTS := $(DERIVED_DATA)/appstore
# App Store Connect sorts screenshots by display class, not by model: the iPhone
# tab that has to be filled is the 6.1"/6.3" one ("iPhone with Dynamic Island,
# medium display"), which takes 1179x2556 or 1206x2622. A 6.9" phone produces
# 1320x2868, which that tab refuses.
SHOT_IPHONE ?= Shot iPhone 6.3
SHOT_IPHONE_TYPE ?= com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
SHOT_IPHONE_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.iOS-27-0
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
# Rewrites a PNG with only the chunks App Store Connect accepts. `sips` and
# ImageIO both stamp an eXIf chunk, and the uploader then refuses the file with
# "File dimensions are invalid" about an image whose dimensions are correct.
PNG_STRIP := python3 tools/strip-png-metadata.py
# Screenshots come out of the simulator with an alpha channel, which App Store
# artwork must not have; this draws them opaque before the strip below.
PNG_FLATTEN := swift tools/flatten-png.swift

.PHONY: all build test typecheck run deploy launch iphones screenshot live icon mapping devices open clean help archive ipa upload check-release shots shots-watch creative screenshots

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
xcrun simctl io '$(1)' screenshot '$(APPSTORE_SHOTS)/$(2).raw.png'; \
$(PNG_FLATTEN) '$(APPSTORE_SHOTS)/$(2).raw.png' '$(APPSTORE_SHOTS)/$(2).png'; \
rm -f '$(APPSTORE_SHOTS)/$(2).raw.png'; \
$(PNG_STRIP) '$(APPSTORE_SHOTS)/$(2).png'
endef

## Capture the App Store screenshots at the two sizes Apple asks for: the largest
## iPhone and the 13-inch iPad. Override the devices with SHOT_IPHONE=/SHOT_IPAD=.
shots: build
	@mkdir -p '$(APPSTORE_SHOTS)'
	@xcrun simctl list devices available | grep -q '$(SHOT_IPHONE) (' || \
		xcrun simctl create '$(SHOT_IPHONE)' $(SHOT_IPHONE_TYPE) $(SHOT_IPHONE_RUNTIME)
	$(call capture-shot,$(SHOT_IPHONE),iphone-6.3)
	$(call capture-shot,$(SHOT_IPAD),ipad-13)
	@echo "wrote $(APPSTORE_SHOTS) - iphone-6.3 is 1206x2622, ipad-13 is 2064x2752"

# The public site: a landing page, the privacy policy and support, in Czech at the
# root and English under /en/. Generated rather than hand-written, so the pages and
# the screenshots stay in step with the app.
SITE_DIR := $(DERIVED_DATA)/site
# Where the site is served from. `make site-deploy` copies the build there.
SITE_HOST ?= deploy@2.31.33.21

## Build the public site into build/site.
site:
	@python3 tools/build-site.py --output '$(SITE_DIR)'
	@echo "built $(SITE_DIR) - serve it with: make site-serve"

## Look at the built site before publishing it.
site-serve: site
	@echo "http://127.0.0.1:8080/"
	@cd '$(SITE_DIR)' && python3 -m http.server 8080

## Publish the site. The old tree is kept as /var/www/vdvlive.old until the next deploy.
site-deploy: site
	rsync -az --delete -e ssh '$(SITE_DIR)/' '$(SITE_HOST):/tmp/site-deploy/'
	ssh $(SITE_HOST) 'set -e; \
		sudo rm -rf /var/www/vdvlive.new; sudo mkdir -p /var/www/vdvlive.new; \
		sudo cp -r /tmp/site-deploy/. /var/www/vdvlive.new/; \
		sudo chown -R www-data:www-data /var/www/vdvlive.new; \
		sudo rm -rf /var/www/vdvlive.old; \
		sudo mv /var/www/vdvlive /var/www/vdvlive.old 2>/dev/null || true; \
		sudo mv /var/www/vdvlive.new /var/www/vdvlive; \
		sudo nginx -t; sudo systemctl reload nginx'
	@echo "published https://vdv.ondralinek.cz/"

## Draw the App Store creative assets: the icon as a bare PNG, and the two wide
## banners the App Store shows on the product page header and in search results.
## Both are optional, and irrelevant to the app icon field, which is 1024 x 1024.
creative:
	@mkdir -p '$(APPSTORE_SHOTS)'
	cp VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
		'$(APPSTORE_SHOTS)/appicon-1024.png'
	swift tools/make-appstore-banner.swift 5244 2950 \
		VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
		'$(APPSTORE_SHOTS)/creative-header-5244x2950.png'
	swift tools/make-appstore-banner.swift 3840 1646 \
		VdvLive/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
		'$(APPSTORE_SHOTS)/creative-header-3840x1646.png'
	$(PNG_STRIP) '$(APPSTORE_SHOTS)/appicon-1024.png' \
		'$(APPSTORE_SHOTS)/creative-header-5244x2950.png' \
		'$(APPSTORE_SHOTS)/creative-header-3840x1646.png'
	@echo "wrote $(APPSTORE_SHOTS) - the icon for the 1024 field, the two banners for the creative asset slots"

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
	xcrun simctl io '$(SHOT_WATCH)' screenshot '$(APPSTORE_SHOTS)/watch-49mm.raw.png'
	$(PNG_FLATTEN) '$(APPSTORE_SHOTS)/watch-49mm.raw.png' '$(APPSTORE_SHOTS)/watch-49mm.png'
	@rm -f '$(APPSTORE_SHOTS)/watch-49mm.raw.png'
	$(PNG_STRIP) '$(APPSTORE_SHOTS)/watch-49mm.png'
	@echo "wrote $(APPSTORE_SHOTS)/watch-49mm.png"

# --- Screenshots kept with the repo ----------------------------------------
#
# The App Store artwork, captured from a clean simulator at the two sizes Apple
# asks for, and on the watch. Screens that need a tap to reach are opened by the
# debug-only launch arguments in `ScreenshotRoute`, so `make screenshots`
# reproduces the same frames on any Mac.
SCREENSHOT_DIR := screenshots
SCREENSHOT_DELAY ?= 15
SCREENSHOT_BOARD_DELAY ?= 40
SCREENSHOT_SERVICE_DELAY ?= 40
SCREENSHOT_WATCH_DELAY ?= 30
# The iPad shows far more of the region at the same span, which turns the markers
# into a crowd, so it opens tighter.
SHOT_IPAD_LATITUDE ?= 49.4
SHOT_IPAD_LONGITUDE ?= 15.6
SHOT_IPAD_LATITUDE_DELTA ?= 0.36
SHOT_IPAD_LONGITUDE_DELTA ?= 0.52
# A stop with enough lines that its board fills the screen, and a line that is
# usually running. Both are text, so a different region needs different values.
SCREENSHOT_ARGS := -screenshotAllVehicles
SCREENSHOT_BOARD_ARGS := $(SCREENSHOT_ARGS) -screenshotDownloadTimetables -screenshotBoard 'Třebíč,aut.nádr.'
SCREENSHOT_SERVICE_ARGS := $(SCREENSHOT_ARGS) -screenshotDownloadTimetables -screenshotExpandTimetable -screenshotService 410

# prepare-shot-device(device, latitude, longitude, latitude delta, longitude delta):
# boot it, make it look like a photograph rather than
# a phone someone has been using, install the app, and seed the preferences that
# keep the map and the permission alert out of the picture.
define prepare-shot-device
@echo "preparing $(1)"; \
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
plutil -insert savedMapView.latitude -float $(2) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.longitude -float $(3) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.latitudeDelta -float $(4) "$$container/Library/Preferences/$(APP_ID).plist"; \
plutil -insert savedMapView.longitudeDelta -float $(5) "$$container/Library/Preferences/$(APP_ID).plist"
endef

# capture-screen(device, path, delay, launch arguments): relaunch the installed app
# with the arguments the shot needs, wait for it to settle, and write a PNG that
# App Store Connect accepts.
define capture-screen
@echo "capturing $(1) -> $(2)"; \
xcrun simctl terminate '$(1)' $(APP_ID) >/dev/null 2>&1 || true; \
xcrun simctl launch '$(1)' $(APP_ID) $(4) >/dev/null; \
sleep $(3); \
xcrun simctl io '$(1)' screenshot '$(2).raw.png'; \
$(PNG_FLATTEN) '$(2).raw.png' '$(2)'; \
rm -f '$(2).raw.png'; \
$(PNG_STRIP) '$(2)'
endef

## Capture the screenshots kept with the repo, for the iPhone, iPad and watch.
screenshots: build watch
	@mkdir -p '$(SCREENSHOT_DIR)/iphone' '$(SCREENSHOT_DIR)/ipad' '$(SCREENSHOT_DIR)/watch'
	@xcrun simctl list devices available | grep -q '$(SHOT_IPHONE) (' || \
		xcrun simctl create '$(SHOT_IPHONE)' $(SHOT_IPHONE_TYPE) $(SHOT_IPHONE_RUNTIME)
	$(call prepare-shot-device,$(SHOT_IPHONE),$(SHOT_LATITUDE),$(SHOT_LONGITUDE),$(SHOT_LATITUDE_DELTA),$(SHOT_LONGITUDE_DELTA))
	$(call capture-screen,$(SHOT_IPHONE),$(SCREENSHOT_DIR)/iphone/01-main.png,$(SCREENSHOT_DELAY),$(SCREENSHOT_ARGS))
	$(call capture-screen,$(SHOT_IPHONE),$(SCREENSHOT_DIR)/iphone/02-settings.png,$(SCREENSHOT_DELAY),$(SCREENSHOT_ARGS) -screenshotSettings)
	$(call capture-screen,$(SHOT_IPHONE),$(SCREENSHOT_DIR)/iphone/03-service-timetable.png,$(SCREENSHOT_SERVICE_DELAY),$(SCREENSHOT_SERVICE_ARGS))
	$(call capture-screen,$(SHOT_IPHONE),$(SCREENSHOT_DIR)/iphone/04-departure-board.png,$(SCREENSHOT_BOARD_DELAY),$(SCREENSHOT_BOARD_ARGS))
	$(call prepare-shot-device,$(SHOT_IPAD),$(SHOT_IPAD_LATITUDE),$(SHOT_IPAD_LONGITUDE),$(SHOT_IPAD_LATITUDE_DELTA),$(SHOT_IPAD_LONGITUDE_DELTA))
	$(call capture-screen,$(SHOT_IPAD),$(SCREENSHOT_DIR)/ipad/01-main.png,$(SCREENSHOT_DELAY),$(SCREENSHOT_ARGS))
	$(call capture-screen,$(SHOT_IPAD),$(SCREENSHOT_DIR)/ipad/02-settings.png,$(SCREENSHOT_DELAY),$(SCREENSHOT_ARGS) -screenshotSettings)
	$(call capture-screen,$(SHOT_IPAD),$(SCREENSHOT_DIR)/ipad/03-service-timetable.png,$(SCREENSHOT_SERVICE_DELAY),$(SCREENSHOT_SERVICE_ARGS))
	$(call capture-screen,$(SHOT_IPAD),$(SCREENSHOT_DIR)/ipad/04-departure-board.png,$(SCREENSHOT_BOARD_DELAY),$(SCREENSHOT_BOARD_ARGS))
	@$(call capture-watch-screens)
	@echo "wrote $(SCREENSHOT_DIR) - iphone 1206x2622, ipad 2064x2752"

# The watch shots: the map, and the detail sheet `-watchSelectFirst` opens. The
# watch reads its pinned lines from its own defaults on a Mac, so two are seeded.
define capture-watch-screens
xcrun simctl boot '$(SHOT_WATCH)' >/dev/null 2>&1 || true; \
xcrun simctl bootstatus '$(SHOT_WATCH)' -b >/dev/null 2>&1 || true; \
xcrun simctl status_bar '$(SHOT_WATCH)' override --time '9:41' --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true; \
xcrun simctl terminate '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null 2>&1 || true; \
xcrun simctl uninstall '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null 2>&1 || true; \
xcrun simctl spawn '$(SHOT_WATCH)' defaults write $(WATCH_ID) favouriteLines \
	-array 358300 764330; \
xcrun simctl install '$(SHOT_WATCH)' '$(WATCH_APP)'; \
xcrun simctl launch '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null; \
sleep $(SCREENSHOT_WATCH_DELAY); \
xcrun simctl io '$(SHOT_WATCH)' screenshot '$(SCREENSHOT_DIR)/watch/01-main.raw.png'; \
$(PNG_FLATTEN) '$(SCREENSHOT_DIR)/watch/01-main.raw.png' '$(SCREENSHOT_DIR)/watch/01-main.png'; \
rm -f '$(SCREENSHOT_DIR)/watch/01-main.raw.png'; \
$(PNG_STRIP) '$(SCREENSHOT_DIR)/watch/01-main.png'; \
xcrun simctl terminate '$(SHOT_WATCH)' $(WATCH_ID) >/dev/null 2>&1 || true; \
xcrun simctl launch '$(SHOT_WATCH)' $(WATCH_ID) -watchSelectFirst >/dev/null; \
sleep 6; \
xcrun simctl io '$(SHOT_WATCH)' screenshot '$(SCREENSHOT_DIR)/watch/02-service.raw.png'; \
$(PNG_FLATTEN) '$(SCREENSHOT_DIR)/watch/02-service.raw.png' '$(SCREENSHOT_DIR)/watch/02-service.png'; \
rm -f '$(SCREENSHOT_DIR)/watch/02-service.raw.png'; \
$(PNG_STRIP) '$(SCREENSHOT_DIR)/watch/02-service.png'
endef

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
