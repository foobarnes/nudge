SHELL := /bin/bash
.DEFAULT_GOAL := help

PACKAGE_DIR := Packages/NudgeKit
APP_NAME    := Nudge
DERIVED     := $(PWD)/DerivedData
INSTALLED   := /Applications/$(APP_NAME).app
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
	-pkill -x $(APP_NAME)
	rm -rf $(INSTALLED) && cp -R $(DERIVED)/Build/Products/Release/$(APP_NAME).app $(INSTALLED)
	open $(INSTALLED)

run-debug: build ## Build Debug and launch it with ARGS (e.g. ARGS="-NudgeFixture path.json")
	-pkill -x $(APP_NAME)
	$(DERIVED)/Build/Products/Debug/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) $(ARGS) &

dmg: gen ## Build Release into build/ and package an unsigned build/Nudge.dmg (doesn't install or relaunch)
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -derivedDataPath $(PWD)/build/DerivedData -quiet build
	scripts/make-dmg.sh $(PWD)/build/DerivedData/Build/Products/Release/$(APP_NAME).app $(PWD)/build/$(APP_NAME).dmg

clean: ## Remove build output and the generated project
	rm -rf $(DERIVED) $(APP_NAME).xcodeproj $(PACKAGE_DIR)/.build
