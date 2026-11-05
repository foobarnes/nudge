SHELL := /bin/bash
.DEFAULT_GOAL := help

PACKAGE_DIR := Packages/NudgeKit
APP_NAME    := Nudge
# The built bundle and process name (PRODUCT_NAME in project.yml); APP_NAME is the Xcode project and scheme.
PRODUCT     := Nudge PRs
DERIVED     := $(PWD)/DerivedData
INSTALLED   := /Applications/$(PRODUCT).app
ARGS        ?=

.PHONY: help bootstrap gen build test run run-debug dmg clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install tooling and generate the Xcode project
	brew bundle --file=Brewfile
	$(MAKE) gen

gen: ## Generate Nudge.xcodeproj from project.yml
	@xcodegen generate --spec project.yml --quiet && echo "Generated $(APP_NAME).xcodeproj"

build: gen ## Build the app (Debug)
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -derivedDataPath $(DERIVED) -quiet build

test: ## Run the package test suite
	cd $(PACKAGE_DIR) && swift test

run: gen ## Build Release, install to /Applications, relaunch
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -derivedDataPath $(DERIVED) -quiet build
	-pkill -x "$(PRODUCT)"
	rm -rf "$(INSTALLED)" && cp -R "$(DERIVED)/Build/Products/Release/$(PRODUCT).app" "$(INSTALLED)"
	open "$(INSTALLED)"

run-debug: build ## Build Debug and launch it with ARGS (e.g. ARGS="-NudgeFixture path.json")
	-pkill -x "$(PRODUCT)"
	"$(DERIVED)/Build/Products/Debug/$(PRODUCT).app/Contents/MacOS/$(PRODUCT)" $(ARGS) &

dmg: gen ## Build Release into build/ and package an unsigned build/Nudge.dmg (doesn't install or relaunch)
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -derivedDataPath $(PWD)/build/DerivedData -quiet build
	scripts/make-dmg.sh "$(PWD)/build/DerivedData/Build/Products/Release/$(PRODUCT).app" $(PWD)/build/$(APP_NAME).dmg

clean: ## Remove build output and the generated project
	rm -rf $(DERIVED) $(APP_NAME).xcodeproj $(PACKAGE_DIR)/.build
