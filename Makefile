APP_NAME    = onit
EXECUTABLE  = Onit
BUNDLE_DIR  = $(APP_NAME).app
DMG         = $(APP_NAME).dmg
ARCHS       = --arch arm64 --arch x86_64
SIGN_IDENTITY  ?= -
NOTARY_PROFILE ?=

# Put SIGN_IDENTITY and NOTARY_PROFILE in .env (not committed) for a Developer ID release.
-include .env

.PHONY: build test bundle sign notarize-app dmg notarize-dmg release run clean icon

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
	cp SupportFiles/Info.plist $(BUNDLE_DIR)/Contents/
	cp SupportFiles/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/AppIcon.icns
	@echo "Bundled: $(BUNDLE_DIR)"

# ── Sign and notarize the app ─────────────────────────
#    Notarizing the .app before it goes into the DMG means the app
#    still passes Gatekeeper after people drag it out.

sign: bundle
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

# ── Release ────────────────────────────────────────────
#    build → bundle → sign → notarize app → dmg → notarize dmg

release: notarize-dmg

# ── Dev ────────────────────────────────────────────────

run: bundle
	codesign --force --sign - $(BUNDLE_DIR)
	open $(BUNDLE_DIR)

icon:
	swift SupportFiles/generate-icon.swift

clean:
	rm -rf .build $(BUNDLE_DIR) $(DMG) $(APP_NAME).zip
