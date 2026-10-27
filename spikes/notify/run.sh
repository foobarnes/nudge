#!/bin/zsh
# Spike 2. Usage: ./run.sh install | log | clean
set -eu
cd ${0:A:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
app=/Applications/NudgeSpikeNotify.app
case ${1:-install} in
install)
  /opt/homebrew/bin/xcodegen generate --quiet
  xcodebuild -project SpikeNotify.xcodeproj -scheme SpikeNotify -configuration Release -sdk macosx \
    -derivedDataPath build/dd build -quiet
  pkill -x NudgeSpikeNotify || true
  [[ -e $app ]] && trash $app
  ditto build/dd/Build/Products/Release/NudgeSpikeNotify.app $app
  codesign -dv $app 2>&1 | grep -E '^(Identifier|Signature)'
  open $app; sleep 4; tail -6 ~/Library/Logs/NudgeSpike/notify.log;;
log) tail -20 ~/Library/Logs/NudgeSpike/notify.log;;
clean)
  pkill -x NudgeSpikeNotify || true
  for p in $app build SpikeNotify.xcodeproj ~/Library/Logs/NudgeSpike; do [[ -e $p ]] && trash $p; done
  tccutil reset AppleEvents io.github.foobarnes.nudge.spike-notify || true
  tccutil reset All io.github.foobarnes.nudge.spike-notify || true;;
esac
