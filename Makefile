SCHEME        = TachToneMac
APP_NAME      = TachToneMac
CONFIGURATION = Release
BUILD_DIR     = build
DERIVED_DATA  = $(BUILD_DIR)/DerivedData
APP_PATH      = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
DMG_NAME      = TachTone
DMG_PATH      = $(BUILD_DIR)/$(DMG_NAME).dmg
DMG_STAGING   = $(BUILD_DIR)/dmg-staging

.PHONY: all build dmg clean

all: dmg

build:
	@echo "→ Building $(APP_NAME) ($(CONFIGURATION))…"
	@xcodebuild \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		-quiet \
		build
	@echo "✓ App: $(APP_PATH)"

dmg: build
	@echo "→ Packaging DMG…"
	@rm -rf "$(DMG_STAGING)" "$(DMG_PATH)"
	@mkdir -p "$(DMG_STAGING)"
	@cp -R "$(APP_PATH)" "$(DMG_STAGING)/$(APP_NAME).app"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@hdiutil create \
		-volname "$(DMG_NAME)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov -format UDZO \
		"$(DMG_PATH)" \
		> /dev/null
	@rm -rf "$(DMG_STAGING)"
	@echo "✓ DMG: $(DMG_PATH)"

clean:
	@rm -rf "$(BUILD_DIR)"
	@echo "✓ Cleaned"
