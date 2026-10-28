#!/usr/bin/env bash
# Packages Nudge.app into the branded install DMG (background, icon layout, volume icon).
#
#   scripts/make-dmg.sh <path/to/Nudge.app> <output.dmg>
#
# Used by the Release workflow and by `make dmg`. Signing and notarization happen afterwards, in the workflow.
# dmgbuild (pinned in scripts/dmg/requirements.txt) is installed into a private venv on first use.
set -euo pipefail

app=${1:?usage: make-dmg.sh <path/to/Nudge.app> <output.dmg>}
out=${2:?usage: make-dmg.sh <path/to/Nudge.app> <output.dmg>}
here=$(cd "$(dirname "$0")" && pwd)
assets="$here/dmg"
venv=${DMGBUILD_VENV:-"$(dirname "$here")/build/dmgbuild-venv"}

[[ -d $app ]] || { echo "error: no app at $app" >&2; exit 1; }

if [[ ! -x $venv/bin/dmgbuild ]] || ! cmp -s "$assets/requirements.txt" "$venv/requirements.txt"; then
  echo "Installing dmgbuild into $venv"
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes -r "$assets/requirements.txt"
  cp "$assets/requirements.txt" "$venv/requirements.txt"
fi

# Volume icon: the app's own icon when it has one, otherwise the committed fallback rendered from the brand SVG.
icon="$app/Contents/Resources/AppIcon.icns"
if [[ ! -f $icon ]]; then
  echo "note: $icon not found; using the fallback volume icon"
  icon="$assets/VolumeIcon.icns"
fi

mkdir -p "$(dirname "$out")"
rm -f "$out"
"$venv/bin/dmgbuild" -s "$assets/settings.py" -D app="$app" -D background="$assets/background.png" \
  -D icon="$icon" Nudge "$out"
echo "Built $out"
