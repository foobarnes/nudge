#!/bin/zsh
# Spike 4. Usage: ./run.sh [demo|interactive|log|clean]. Runs from build/, no install needed.
set -eu
cd ${0:A:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
app=build/dd/Build/Products/Debug/NudgeSpikePanel.app
front() { osascript -e 'tell application "System Events" to name of first application process whose frontmost is true'; }
build() {
  /opt/homebrew/bin/xcodegen generate --quiet
  xcodebuild -project SpikePanel.xcodeproj -scheme SpikePanel -configuration Debug -sdk macosx \
    -derivedDataPath build/dd build -quiet
  pkill -x NudgeSpikePanel || true
}
case ${1:-demo} in
demo|interactive)
  build
  echo "frontmost before: $(front)"
  if [[ $1 == demo ]]; then open $app --args --demo; else open $app; fi
  sleep 1; echo "frontmost after launch: $(front)"
  [[ $1 == demo ]] && { sleep 2; echo "frontmost while expanded: $(front)"; }
  tail -6 ~/Library/Logs/NudgeSpike/panel.log;;
log) tail -30 ~/Library/Logs/NudgeSpike/panel.log;;
clean)
  pkill -x NudgeSpikePanel || true
  for p in build SpikePanel.xcodeproj ~/Library/Logs/NudgeSpike/panel.log; do [[ -e $p ]] && trash $p; done;;
esac
