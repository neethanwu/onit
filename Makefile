APP_NAME    = onit
EXECUTABLE  = Onit
BUNDLE_DIR  = $(APP_NAME).app
SIGN_IDENTITY ?= -

-include .env

.PHONY: build test bundle sign run clean

build:
	swift build -c release

test:
	swift test

bundle: build
	@rm -rf $(BUNDLE_DIR)
	@mkdir -p $(BUNDLE_DIR)/Contents/MacOS
	cp .build/release/$(EXECUTABLE) $(BUNDLE_DIR)/Contents/MacOS/$(EXECUTABLE)
	cp SupportFiles/Info.plist $(BUNDLE_DIR)/Contents/
	@echo "Bundled: $(BUNDLE_DIR)"

sign: bundle
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" $(BUNDLE_DIR)
	@echo "Signed: $(BUNDLE_DIR)"

run: bundle
	codesign --force --sign - $(BUNDLE_DIR)
	open $(BUNDLE_DIR)

clean:
	rm -rf .build $(BUNDLE_DIR)
