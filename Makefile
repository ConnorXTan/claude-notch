# claude-notch — the notch as a status light for Claude Code.
#
#   make app        build/ClaudeNotch.app, the release bundle
#   make run        build the app and open it
#   make swift      debug build (swift build)
#   make test       the unit tests (swift test)
#   make icon       just the generated icon
#   make clean      remove build/

BUILD := build

.PHONY: all app run swift test swift-test icon clean help

all: app

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

help:
	@sed -n '2,8p' Makefile | sed 's/^# \{0,1\}//'

# The Swift package (Package.swift) builds the notch app; this wraps the
# release binary as a bundle so Launch Services treats it as an app (menu bar
# extra, LSUIElement, Automation permission for terminal focus).

APP        := $(BUILD)/ClaudeNotch.app
ICNS       := $(BUILD)/ClaudeNotch.icns
SWIFT_REL  := .build/release/ClaudeNotch
SWIFT_SRC  := Package.swift $(shell find ClaudeNotch -type f 2>/dev/null)

$(ICNS): tools/mkicon.swift | $(BUILD)
	swift tools/mkicon.swift $(BUILD)/ClaudeNotch.iconset
	iconutil -c icns $(BUILD)/ClaudeNotch.iconset -o $(ICNS)

icon: $(ICNS)

swift:
	swift build

test swift-test:
	swift test

app: $(APP)

$(APP): $(SWIFT_SRC) $(ICNS)
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(SWIFT_REL) $(APP)/Contents/MacOS/ClaudeNotch
	cp ClaudeNotch/Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/ClaudeNotch.icns
	codesign --force --sign - $(APP)
	@echo "built $(APP)"

run: app
	open $(APP)
