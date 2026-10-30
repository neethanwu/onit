APP_NAME    = onit
EXECUTABLE  = Onit
BUNDLE_DIR  = $(APP_NAME).app
DMG         = $(APP_NAME).dmg
ARCHS       = --arch arm64 --arch x86_64
SIGN_IDENTITY  ?= -
NOTARY_PROFILE ?=
VERSION     = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" SupportFiles/Info.plist)
SPARKLE_BIN = .build/artifacts/sparkle/Sparkle/bin
SPARKLE     = $(BUNDLE_DIR)/Contents/Frameworks/Sparkle.framework

# Put SIGN_IDENTITY and NOTARY_PROFILE in .env (not committed) for a Developer ID release.
-include .env

.PHONY: build test bundle sign notarize-app dmg notarize-dmg appcast release run clean icon

# ── Build ──────────────────────────────────────────────
#    Universal: runs on Apple silicon and Intel Macs.

build:
	swift build -c release $(ARCHS)

test:
	swift test

# ── Bundle ─────────────────────────────────────────────

bundle: build
	@rm -rf $(BUNDLE_DIR)
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS $(BUNDLE_DIR)/Contents/Resources
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/$(EXECUTABLE)" $(BUNDLE_DIR)/Contents/MacOS/$(EXECUTABLE)
	@mkdir -p $(BUNDLE_DIR)/Contents/Frameworks
	ditto "$$(swift build -c release $(ARCHS) --show-bin-path)/Sparkle.framework" $(SPARKLE)
	@# onit isn't sandboxed, so Sparkle's XPC services aren't needed.
	rm -rf $(SPARKLE)/Versions/B/XPCServices $(SPARKLE)/XPCServices
	cp SupportFiles/Info.plist $(BUNDLE_DIR)/Contents/
	cp SupportFiles/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/AppIcon.icns
	@echo "Bundled: $(BUNDLE_DIR)"

# ── Sign and notarize the app ─────────────────────────
#    Notarizing the .app before it goes into the DMG means the app
#    still passes Gatekeeper after people drag it out.

sign: bundle
	@# Sign Sparkle from the inside out, then the app.
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(SPARKLE)/Versions/B/Autoupdate
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(SPARKLE)/Versions/B/Updater.app
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(SPARKLE)
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(BUNDLE_DIR)
	codesign --verify --strict --verbose=2 $(BUNDLE_DIR)
	@echo "Signed: $(BUNDLE_DIR)"

notarize-app: sign
	@test -n "$(NOTARY_PROFILE)" || (echo "Set NOTARY_PROFILE in .env" && exit 1)
	@rm -f $(APP_NAME).zip
	ditto -c -k --keepParent $(BUNDLE_DIR) $(APP_NAME).zip
	xcrun notarytool submit $(APP_NAME).zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(BUNDLE_DIR)
	@rm -f $(APP_NAME).zip
	@echo "Notarized: $(BUNDLE_DIR)"

# ── DMG ────────────────────────────────────────────────

dmg: notarize-app
	@rm -f $(DMG)
	create-dmg \
		--volname "$(APP_NAME)" \
		--volicon SupportFiles/AppIcon.icns \
		--window-size 500 340 \
		--icon-size 96 \
		--icon "$(BUNDLE_DIR)" 130 150 \
		--app-drop-link 370 150 \
		--hide-extension "$(BUNDLE_DIR)" \
		$(DMG) $(BUNDLE_DIR)
	codesign --force --timestamp --sign "$(SIGN_IDENTITY)" $(DMG)
	@echo "Created: $(DMG)"

notarize-dmg: dmg
	xcrun notarytool submit $(DMG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature --verbose $(DMG)
	@echo "Notarized: $(DMG)"

# ── Appcast ────────────────────────────────────────────
#    The update feed. Signs the DMG with the EdDSA key in the login keychain (account
#    "onit") and writes appcast.xml; upload both to the GitHub release for v$(VERSION).

appcast: notarize-dmg
	@rm -rf build/appcast && mkdir -p build/appcast
	cp $(DMG) build/appcast/
	$(SPARKLE_BIN)/generate_appcast --account onit \
		--download-url-prefix https://github.com/neethanwu/onit/releases/download/v$(VERSION)/ \
		build/appcast
	cp build/appcast/appcast.xml appcast.xml
	@echo "Wrote appcast.xml for v$(VERSION)"

# ── Release ────────────────────────────────────────────
#    build → bundle → sign → notarize app → dmg → notarize dmg → appcast

release: appcast

# ── Dev ────────────────────────────────────────────────

run: bundle
	codesign --force --deep --sign - $(BUNDLE_DIR)
	open $(BUNDLE_DIR)

icon:
	swift SupportFiles/generate-icon.swift

clean:
	rm -rf .build build $(BUNDLE_DIR) $(DMG) $(APP_NAME).zip appcast.xml
