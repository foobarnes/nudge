SHELL := /bin/bash
.DEFAULT_GOAL := help

PACKAGE_DIR := Packages/NudgeKit
APP_NAME    := Nudge
# Debug builds are a separate app, "Nudge Dev" (its own bundle ID), so they never touch the installed release.
# Bundle and process names come from PRODUCT_NAME / EXECUTABLE_NAME in project.yml.
DEV_BUNDLE  := Nudge Dev
DEV_PROCESS := Nudge PRs Dev
DERIVED     := $(PWD)/DerivedData
DEV_APP     := $(DERIVED)/Build/Products/Debug/$(DEV_BUNDLE).app
ARGS        ?=

.PHONY: help bootstrap gen build test run stop dmg clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install tooling and generate the Xcode project
	brew bundle --file=Brewfile
	$(MAKE) gen

gen: ## Generate Nudge.xcodeproj from project.yml
	@xcodegen generate --spec project.yml --quiet && echo "Generated $(APP_NAME).xcodeproj"

build: gen ## Build the dev app (Debug)
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Debug -derivedDataPath $(DERIVED) -quiet build

test: ## Run the package test suite
	cd $(PACKAGE_DIR) && swift test

run: build stop ## Build and run the dev app in the foreground with ARGS (e.g. ARGS="-NudgeFixture path.json"); Ctrl-C quits
	-"$(DEV_APP)/Contents/MacOS/$(DEV_PROCESS)" $(ARGS)

stop: ## Quit every running dev build, from any worktree (never the installed release)
	@pkill -x "$(DEV_PROCESS)" && echo "Stopped running dev builds" || true

dmg: gen ## Build Release into build/ and package an unsigned build/Nudge.dmg (doesn't install or launch)
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -derivedDataPath $(PWD)/build/DerivedData -quiet build
	scripts/make-dmg.sh "$(PWD)/build/DerivedData/Build/Products/Release/$(APP_NAME).app" $(PWD)/build/$(APP_NAME).dmg

clean: stop ## Quit dev builds, then remove build output and the generated project
	rm -rf $(DERIVED) $(APP_NAME).xcodeproj $(PACKAGE_DIR)/.build
