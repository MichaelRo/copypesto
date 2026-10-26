DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
BUILD_DIR      = .build/xcode
ARCHIVE_PATH   = $(BUILD_DIR)/Pesto.xcarchive
EXPORT_PATH    = $(BUILD_DIR)/export
# Set APPLE_TEAM_ID in your environment or pass it on the command line.
APPLE_TEAM_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep 'Developer ID Application' \
	| head -1 \
	| sed -n 's/.*(\([A-Z0-9]*\))".*/\1/p')

XCODEBUILD = DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
	-project Pesto.xcodeproj \
	-scheme Pesto \
	-configuration Debug \
	-destination 'platform=macOS' \
	-derivedDataPath $(BUILD_DIR) \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO

APP              = $(BUILD_DIR)/Build/Products/Debug/Pesto.app
DEV_SIGN_IDENTITY = Pesto Development
RELEASE_SIGN_IDENTITY = Pesto Release
ENTITLEMENTS      = Sources/Resources/Pesto.entitlements

.DEFAULT_GOAL := help

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: help
help: ## [Develop] Show this help
	@awk -F':[^#]*## ' '/^[a-zA-Z_-]+:[^#]*## \[/ { match($$2,/^\[[^]]+\]/); g=substr($$2,2,RLENGTH-2); d=substr($$2,RLENGTH+2); line[g]=line[g] sprintf("  \033[36m%-20s\033[0m %s\n",$$1,d) } END { n=split("Develop Test Benchmarks Release Maintenance",o," "); for(i=1;i<=n;i++) if (line[o[i]]!="") printf "\n\033[1m%s\033[0m\n%s",o[i],line[o[i]] }' $(MAKEFILE_LIST)

.PHONY: generate
generate: ## [Develop] Regenerate Pesto.xcodeproj from Pesto.yml (and restore the committed package pins)
	xcodegen generate --spec Pesto.yml
	mkdir -p Pesto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	cp Pesto.resolved Pesto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

.PHONY: update-resolved
update-resolved: generate ## [Develop] Re-resolve packages and save the exact revisions to Pesto.resolved (review the diff, commit it)
	rm -f Pesto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project Pesto.xcodeproj -scheme Pesto -derivedDataPath $(BUILD_DIR) -resolvePackageDependencies
	cp Pesto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Pesto.resolved

.PHONY: build
build: generate ## [Develop] Build the app (debug, no signing)
	$(XCODEBUILD) PESTO_DEV_BUILD=YES build

.PHONY: check-signing
check-signing:
	@if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$(DEV_SIGN_IDENTITY)"; then \
		echo ""; \
		echo "  error: '$(DEV_SIGN_IDENTITY)' code-signing cert not found."; \
		echo ""; \
		echo "  Pesto needs a stable signing identity so macOS treats every rebuild"; \
		echo "  as the SAME app. Without it the Accessibility grant and Keychain"; \
		echo "  'Always Allow' will reset on every 'make run'."; \
		echo ""; \
		echo "  Fix: run 'make setup-signing' once."; \
		echo ""; \
		exit 1; \
	fi

# A development build is the shipped app: the same bundle identifier, store, preferences and Keychain key. Starting it
# quits any Pesto that is running, so it refuses to quit one that is not a development build of this checkout.
.PHONY: check-other-pesto
check-other-pesto:
	@for pid in $$(pgrep -x Pesto); do \
		exe=$$(ps -p $$pid -o comm=); app="$${exe%/Contents/MacOS/*}"; \
		kind=$$(defaults read "$$app/Contents/Info" PestoDevelopmentBuild 2>/dev/null || true); \
		if [ "$$kind" != "YES" ] && [ -z "$$PESTO_REPLACE" ]; then \
			echo ""; \
			echo "  error: $$app is running and is not a development build."; \
			echo "  A development build uses the same store, preferences and Keychain key as the installed Pesto,"; \
			echo "  and make run quits the one that is open. Quit it yourself, or run: PESTO_REPLACE=1 make run"; \
			echo ""; \
			exit 1; \
		fi; \
	done

.PHONY: run
run: check-signing check-other-pesto build ## [Develop] Build, sign for stable Accessibility permission, and launch Pesto.app
	codesign -f -s "$(DEV_SIGN_IDENTITY)" \
		--entitlements Sources/Controls/PestoControls.entitlements \
		"$(APP)/Contents/PlugIns/PestoControls.appex"
	codesign -f -s "$(DEV_SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP)"
	@pkill -x Pesto 2>/dev/null || true
	@sleep 0.4
	open $(APP)

RELEASE_BUILD_DIR = .build/xcode-release
RELEASE_APP       = $(RELEASE_BUILD_DIR)/Build/Products/Release/Pesto.app

.PHONY: install
install: check-signing check-other-pesto generate ## [Develop] Build an optimised copy, sign, put it in ~/Applications and launch it (launch at login needs an installed copy)
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Release \
		-destination 'platform=macOS' -derivedDataPath $(RELEASE_BUILD_DIR) \
		PESTO_DEV_BUILD=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
	rm -rf "$(RELEASE_APP)"/Contents/PlugIns/*.xctest "$(RELEASE_APP)"/Contents/PlugIns/*.xctest.dSYM
	codesign -f -s "$(DEV_SIGN_IDENTITY)" \
		--entitlements Sources/Controls/PestoControls.entitlements \
		"$(RELEASE_APP)/Contents/PlugIns/PestoControls.appex"
	codesign -f -s "$(DEV_SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" \
		"$(RELEASE_APP)"
	@pkill -x Pesto 2>/dev/null || true
	@sleep 0.4
	@mkdir -p "$$HOME/Applications"
	rm -rf "$$HOME/Applications/Pesto.app"
	ditto "$(RELEASE_APP)" "$$HOME/Applications/Pesto.app"
	open "$$HOME/Applications/Pesto.app"

MARKETING_TESTS = -only-testing:PestoUITests/MarketingScreenshotTests

# A UI-test runner built unsigned is refused by macOS ("is damaged"); the gate signs it ad hoc, and so do these.
UI_SIGNING = CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

.PHONY: marketing-images
marketing-images: generate ## [Maintenance] Take the website screenshots into .build/marketing/ (the website repo copies them from there); quit other apps first
	@# A test that fails (the Ask picture needs Apple Intelligence) must not stop the pictures that were taken from
	@# being exported; the run still ends with the tests' own status.
	@status=0; \
	$(XCODEBUILD) $(UI_SIGNING) $(MARKETING_TESTS) test || status=$$?; \
	scripts/export-marketing-images.sh; \
	exit $$status

.PHONY: marketing-loops
marketing-loops: generate ## [Maintenance] Take the frames of the website's scenes into .build/marketing/loops/ and make the MP4, WebM and GIF for the README and launch posts in .build/marketing/video/ (needs ffmpeg and gifski); quit other apps first
	@status=0; \
	$(XCODEBUILD) $(UI_SIGNING) -only-testing:PestoUITests/MarketingLoopTests test || status=$$?; \
	scripts/export-marketing-images.sh; \
	scripts/encode-marketing-loops.sh; \
	exit $$status

.PHONY: capture-real
capture-real: generate ## [Maintenance] Retake the Touch ID lock and the Ask pictures with the real Touch ID view and the on-device model (needs Touch ID and Apple Intelligence; stay at the Mac; docs/testing.md)
	@status=0; \
	TEST_RUNNER_PESTO_REAL_DEVICE_CAPTURE=1 $(XCODEBUILD) $(UI_SIGNING) -only-testing:PestoUITests/RealDeviceCaptureTests test || status=$$?; \
	scripts/export-real-device-images.sh; \
	exit $$status

.PHONY: setup-signing
setup-signing: ## [Develop] Create a local dev signing cert so Accessibility permission survives rebuilds (run once; says what it changes)
	@DEV_SIGN_IDENTITY="$(DEV_SIGN_IDENTITY)" scripts/setup-signing.sh

.PHONY: setup-release-signing
setup-release-signing: ## [Release] Create the self-signed "Pesto Release" identity that signs the unsigned 1.0 disk image (run once; says what it changes)
	@SETUP_TARGET=setup-release-signing DEV_SIGN_IDENTITY="$(RELEASE_SIGN_IDENTITY)" scripts/setup-signing.sh

APP_SUPPORT_DIR = $(HOME)/Library/Application Support/net.copypesto.pesto

# A development build shares the shipped identity (bundle ID, Keychain item, preferences, store), so a reset deletes the
# real history of the Mac it runs on. Targets that delete such state depend on this one.
.PHONY: require-dev-reset
require-dev-reset:
	@if [ "$$PESTO_DEV_RESET" != "1" ]; then \
		echo "error: this deletes state of the installed Pesto (Keychain key, preferences, history) on this Mac."; \
		echo "       Run it as: PESTO_DEV_RESET=1 make $(MAKECMDGOALS)"; \
		exit 1; \
	fi

.PHONY: reset-onboarding
reset-onboarding: require-dev-reset ## [Maintenance] Clear the onboarding flag and the Accessibility grant so the welcome screen shows again; keeps your history and its key (use reset-fresh-install for an empty first run)
	@echo "Resetting Pesto first-run state…"
	@pkill -x Pesto 2>/dev/null || true
	@xcrun tccutil reset Accessibility net.copypesto.pesto 2>/dev/null || true
	@if [ -e "$(APP_SUPPORT_DIR)/clips.store" ]; then \
		echo "  keeping the Keychain key: a history exists in $(APP_SUPPORT_DIR) and would become unreadable"; \
	else \
		security delete-generic-password -s net.copypesto.pesto -a net.copypesto.pesto.blobKey 2>/dev/null || true; \
	fi
	@defaults delete net.copypesto.pesto hasOnboarded 2>/dev/null || true
	@echo "✓ Onboarding state cleared. Run 'make run' to see the first-run flow."

.PHONY: reset-fresh-install
reset-fresh-install: require-dev-reset ## [Maintenance] A first run with an empty history: moves the history aside (never deletes it, the key stays so it can be moved back), clears the onboarding flag, welcome samples and Accessibility grant
	@echo "Preparing a fresh first run…"
	@pkill -x Pesto 2>/dev/null || true
	@xcrun tccutil reset Accessibility net.copypesto.pesto 2>/dev/null || true
	@if [ -e "$(APP_SUPPORT_DIR)" ]; then \
		aside="$(APP_SUPPORT_DIR).aside-$$(date +%Y%m%d-%H%M%S)"; \
		mv "$(APP_SUPPORT_DIR)" "$$aside"; \
		echo "  history moved to $$aside (move it back to restore it)"; \
	fi
	@defaults delete net.copypesto.pesto hasOnboarded 2>/dev/null || true
	@defaults delete net.copypesto.pesto samplesSeeded 2>/dev/null || true
	@echo "✓ Run 'make run' to see the first-run flow with an empty shelf."

.PHONY: test-core
test-core: ## [Test] Run Core/ unit tests via SPM — fast, no Xcode project needed
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift test

.PHONY: test
test: generate ## [Test] Run integration tests via xcodebuild (snapshot + UI tests skipped)
	-@caffeinate -u -t 3
	caffeinate -dis env $(XCODEBUILD) \
		-skip-testing:PestoSnapshotTests \
		-skip-testing:PestoUITests \
		test

.PHONY: test-snapshots
test-snapshots: generate ## [Test] Record/verify snapshot baselines (only on the macOS in Tests/PestoSnapshotTests/baseline-macos; run locally)
	@scripts/snapshot-os.sh || { [ "$$PESTO_SNAPSHOT_OS_OVERRIDE" = 1 ] || { echo "Run on the recorded macOS, or re-record on this one with PESTO_SNAPSHOT_OS_OVERRIDE=1 and update baseline-macos"; exit 1; }; }
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project Pesto.xcodeproj \
		-scheme PestoSnapshotTests \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
		test

.PHONY: test-ui
test-ui: generate ## [Test] Run XCUITest flows (PestoUITests target)
	-@caffeinate -u -t 3
	caffeinate -dis env $(XCODEBUILD) $(UI_SIGNING) -only-testing:PestoUITests test

.PHONY: lint
lint: ## [Develop] Check formatting (swiftformat) and lint (swiftlint --strict)
	swiftformat --lint --cache ignore .
	DEVELOPER_DIR=$(DEVELOPER_DIR) swiftlint --strict

.PHONY: lint-analyze
lint-analyze: generate ## [Develop] Find unused imports (a full Debug build first, so it is not part of the gate)
	$(XCODEBUILD) clean build > .build/lint-analyze.log 2>&1
	DEVELOPER_DIR=$(DEVELOPER_DIR) swiftlint analyze --strict --compiler-log-path .build/lint-analyze.log

.PHONY: format
format: ## [Develop] Auto-format all Swift sources with swiftformat
	swiftformat .

.PHONY: check-release-placeholders
check-release-placeholders:
	@if grep -q "REPLACE_WITH_EDDSA_PUBLIC_KEY\|YOUR_APPCAST_URL" Sources/Resources/Info.plist; then \
		echo "error: Info.plist still contains placeholder values. Run generate_keys and set SUFeedURL before archiving."; \
		exit 1; \
	fi

.PHONY: require-team
require-team:
	@echo "$(APPLE_TEAM_ID)" | grep -Eq '^[A-Z0-9]{10}$$' || { \
		echo "error: APPLE_TEAM_ID is '$(APPLE_TEAM_ID)'. Install the Developer ID Application certificate or pass APPLE_TEAM_ID=XXXXXXXXXX."; \
		exit 1; \
	}

.PHONY: archive
archive: check-release-placeholders require-team generate ## [Release] Build a release archive (requires Developer ID certificate)
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project Pesto.xcodeproj \
		-scheme Pesto \
		-configuration Release \
		-destination 'platform=macOS' \
		-archivePath $(ARCHIVE_PATH) \
		DEVELOPMENT_TEAM=$(APPLE_TEAM_ID) \
		archive

.PHONY: export
export: archive ## [Release] Export and sign the archive for Developer ID distribution
	scripts/render-export-options.sh "$(APPLE_TEAM_ID)" $(BUILD_DIR)/exportOptions.plist
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist $(BUILD_DIR)/exportOptions.plist

.PHONY: notarize
notarize: export ## [Release] Notarize, wait for Apple's response, and staple the ticket
	ditto -c -k --keepParent $(EXPORT_PATH)/Pesto.app $(EXPORT_PATH)/Pesto.app.zip
	xcrun notarytool submit $(EXPORT_PATH)/Pesto.app.zip \
		--keychain-profile pesto-notarytool \
		--wait
	xcrun stapler staple $(EXPORT_PATH)/Pesto.app
	spctl --assess --type execute --verbose $(EXPORT_PATH)/Pesto.app

VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(EXPORT_PATH)/Pesto.app/Contents/Info.plist 2>/dev/null)
DMG      = $(EXPORT_PATH)/Pesto-$(VERSION).dmg
SIGN_ID ?= Developer ID Application

.PHONY: dmg
dmg: notarize ## [Release] Package the notarized app into a signed, notarized, stapled DMG (the file Sparkle serves)
	rm -f $(EXPORT_PATH)/Pesto-*.dmg $(EXPORT_PATH)/Pesto-*.dmg.sha256
	scripts/make-dmg.sh $(EXPORT_PATH)/Pesto.app $(DMG)
	codesign --force --sign "$(SIGN_ID)" --timestamp $(DMG)
	xcrun notarytool submit $(DMG) --keychain-profile pesto-notarytool --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature --verbose $(DMG)
	(cd $(EXPORT_PATH) && shasum -a 256 Pesto-$(VERSION).dmg > Pesto-$(VERSION).dmg.sha256)

.PHONY: release-check
release-check: ## [Release] Build the Release configuration unsigned, ad-hoc sign it with the hardened runtime and verify the bundle
	scripts/check-release-build.sh

.PHONY: release-unsigned
release-unsigned: generate ## [Release] Build Release, sign it with "Pesto Release" (no hardened runtime), write .build/release-unsigned/Pesto-<version>.dmg and its .sha256
	PESTO_RELEASE_IDENTITY="$(RELEASE_SIGN_IDENTITY)" scripts/release-unsigned.sh

.PHONY: bench-latency
bench-latency: ## [Benchmarks] Measure paste and copy latency per kind of clip with a real target app; uses the real clipboard (restored), Mac left alone
	scripts/bench-latency.sh

.PHONY: bench-undo
bench-undo: generate ## [Benchmarks] Measure what Undo costs over a 5,000-clip store (recording, restoring, edits, the full stack's memory); prints PERF lines and fails over budget
	@mkdir -p $(BUILD_DIR)
	caffeinate -dis env $(XCODEBUILD) \
		-only-testing:PestoTests/UndoPerformanceTests \
		-only-testing:PestoTests/UndoHistoryMemoryTests \
		test 2>&1 | tee $(BUILD_DIR)/bench-undo.log | grep -E "PERF|error:|Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)"

.PHONY: bench-scroll
bench-scroll: ## [Benchmarks] Measure shelf scrolling (hitches) on a mixed history and a long text history; the Mac must be unlocked
	scripts/bench-scroll.sh

.PHONY: dmg-preview
dmg-preview: generate ## [Release] Build an unsigned installer disk image from a Release build, and open it to look at its window (.build/Pesto-preview.dmg)
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Release \
		-destination 'platform=macOS' -derivedDataPath $(RELEASE_BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
	rm -rf "$(RELEASE_APP)"/Contents/PlugIns/*.xctest "$(RELEASE_APP)"/Contents/PlugIns/*.xctest.dSYM
	scripts/make-dmg.sh "$(RELEASE_APP)" .build/Pesto-preview.dmg
	open .build/Pesto-preview.dmg

.PHONY: release
release: dmg ## [Release] Full release pipeline: archive → export → notarize app → DMG → notarize + staple DMG
	@echo "✓ $(DMG) ready. Next: docs/release.md (sign the appcast item, publish)."

.PHONY: publish-release
publish-release: ## [Release] Run checks and package the release DMG
	scripts/publish-release.sh


.PHONY: build-cli
build-cli: ## [Develop] Build the pesto CLI via SPM
	DEVELOPER_DIR=$(DEVELOPER_DIR) swift build --product PestoCLI

.PHONY: install-cli
install-cli: build-cli ## [Develop] Build and link the pesto CLI into /usr/local/bin, or ~/.local/bin when that cannot be written
	.build/debug/PestoCLI install
	@echo "Installed pesto CLI → /usr/local/bin/pesto"

.PHONY: logs
logs: ## [Develop] Stream Pesto's log output; CATEGORY=paste narrows it to one logger category
	log stream --predicate 'subsystem == "net.copypesto.pesto"$(if $(CATEGORY), AND category == "$(CATEGORY)")' --level debug --color always

.PHONY: reset-dev-state
reset-dev-state: require-dev-reset ## [Maintenance] Clear all macOS dev-state pollution for net.copypesto.pesto — TCC, UserDefaults, stale bundles, menu-bar registry
	@echo "→ Killing any running Pesto processes…"
	-@killall Pesto 2>/dev/null; true
	@echo "→ Resetting TCC entries for net.copypesto.pesto (Accessibility, AppleEvents, etc.)…"
	-@tccutil reset All net.copypesto.pesto 2>/dev/null; true
	@echo "→ Clearing preferences…"
	-@defaults delete net.copypesto.pesto 2>/dev/null; true
	@echo "→ Removing app-state directories…"
	-@rm -rf ~/Library/Caches/net.copypesto.pesto 2>/dev/null
	-@rm -rf ~/Library/HTTPStorages/net.copypesto.pesto 2>/dev/null
	-@rm -rf ~/Library/Saved\ Application\ State/net.copypesto.pesto.savedState 2>/dev/null
	@echo "→ Looking for stale Pesto.app bundles outside this project…"
	@stale="$$(find ~/Applications /Applications -maxdepth 2 -name "Pesto.app" 2>/dev/null | grep -v "$(PWD)" || true)"; \
		if [ -n "$$stale" ]; then \
			echo "$$stale"; \
			echo ""; \
			echo "  Stale bundles listed above. Remove them manually if any are unwanted —"; \
			echo "  duplicate signed copies are a common source of menu-bar ghost entries."; \
			echo ""; \
		else \
			echo "  (none found — good)"; \
		fi
	@echo "→ Restarting Control Center to force menu-bar registry refresh…"
	-@killall ControlCenter 2>/dev/null; true
	@echo ""
	@echo "✓ Dev state reset."
	@echo ""
	@echo "  Next steps:"
	@echo "  1. Run 'make setup-signing' if you haven't already."
	@echo "  2. Run 'make run' — Pesto will prompt for Accessibility once."
	@echo "  3. Grant Accessibility in System Settings → Privacy & Security."
	@echo ""

.PHONY: doctor
doctor: ## [Develop] Print dev-environment diagnostics — signing identity, CDHash, Accessibility grant, a few preferences
	@echo "Pesto dev-environment diagnostics"
	@echo "================================="
	@echo ""
	@echo "→ Signing identity"
	@if security find-identity -v -p codesigning 2>/dev/null | grep -q "$(DEV_SIGN_IDENTITY)"; then \
		echo "  ✓ '$(DEV_SIGN_IDENTITY)' cert present"; \
	else \
		echo "  ✗ '$(DEV_SIGN_IDENTITY)' cert MISSING — run 'make setup-signing'"; \
	fi
	@echo ""
	@echo "→ Last-built bundle"
	@if [ -d "$(APP)" ]; then \
		echo "  Path: $(APP)"; \
		echo "  CDHash:"; \
		codesign -dvvv "$(APP)" 2>&1 | grep -E 'CDHash|TeamIdentifier|Identifier=' | sed 's/^/    /'; \
	else \
		echo "  (no build yet — run 'make build')"; \
	fi
	@echo ""
	@echo "→ Accessibility permission for current bundle"
	@if [ -d "$(APP)" ]; then \
		BID=$$(defaults read "$(APP)/Contents/Info" CFBundleIdentifier 2>/dev/null); \
		echo "  Bundle ID: $$BID"; \
		echo "  (AX grant is per-CDHash; if you see permission prompts on every run, signing is unstable)"; \
	fi
	@echo ""
	@echo "→ A few preferences"
	@echo "  showMenuBarIcon:       $$(defaults read net.copypesto.pesto showMenuBarIcon 2>/dev/null || echo '<unset, defaults to true>')"
	@echo "  appearanceMode:        $$(defaults read net.copypesto.pesto appearanceMode 2>/dev/null || echo '<unset, defaults to system>')"
	@echo "  appTheme:              $$(defaults read net.copypesto.pesto appTheme 2>/dev/null || echo '<unset, defaults to basil>')"
	@echo ""
	@echo "→ Running Pesto processes"
	@pgrep -lf Pesto.app 2>/dev/null | sed 's/^/  /' || echo "  (none)"
	@echo ""
	@echo "→ Stale Pesto.app bundles (outside this project)"
	@find ~/Applications /Applications -maxdepth 2 -name "Pesto.app" 2>/dev/null \
		| grep -v "$(PWD)" | sed 's/^/  /' || true
	@echo ""
	@echo "If something looks wrong, run 'PESTO_DEV_RESET=1 make reset-dev-state' (it deletes this Mac's Pesto preferences)."

.PHONY: verify
verify: ## [Test] Full gate: lint, Core tests, build, hosted + UI tests, screenshots (scripts/verify.sh; about 40 minutes with the UI tests)
	scripts/verify.sh

.PHONY: verify-changed
verify-changed: ## [Test] Lint, Core and hosted tests, plus only the UI suites the changed files can affect (scripts/verify-changed.sh)
	scripts/verify-changed.sh

.PHONY: verify-fast
verify-fast: ## [Test] Lint, Core tests and a Debug build only (scripts/verify.sh --fast)
	scripts/verify.sh --fast

.PHONY: clean
clean: ## [Maintenance] Delete local build artifacts (.build/xcode, xcode-release, xcode-profile)
	rm -rf $(BUILD_DIR) .build/xcode-release .build/xcode-profile

.PHONY: clean-test-defaults
clean-test-defaults: ## [Maintenance] Remove leftover test preference files from ~/Library/Preferences
	scripts/clean-test-defaults.sh

.PHONY: clean-test-keychain
clean-test-keychain: ## [Maintenance] Remove leftover test Keychain items from the login keychain
	scripts/clean-test-keychain.sh --delete

