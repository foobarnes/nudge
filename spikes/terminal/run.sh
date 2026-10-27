#!/bin/zsh
# Spike 3: injection safety + Ghostty + Terminal.app launch. Usage: ./run.sh [ghostty|terminal|inject|all]
set -u
here=${0:A:h}; out=${TMPDIR:-/tmp}/nudge-spike-terminal; mkdir -p $out
swiftc -O $here/render.swift -o $out/render || exit 1
r() { $out/render "$@" https://github.com/acme/api/pull/4211; }
inject() {
  rm -f $out/pwned*
  local t="Fix \"auth\" \$(touch $out/pwned1) \`touch $out/pwned2\` '; touch $out/pwned3; ' \${(e)\$(touch $out/pwned4)} *"
  /bin/zsh -l "$(r 'printf "%s\n" "{title}"; echo {title}; x=$(echo {title}); print -r -- "sub:$x"' "$t")"
  ls $out/pwned* 2>/dev/null && echo "inject: FAIL" || echo "inject: PASS (no marker files)"
}
wait_for() { for i in {1..20}; do [[ -e $1 ]] && { echo "$2: PASS after ${i}s: $(<$1)"; return; }; sleep 1; done; echo "$2: FAIL"; }
ghostty() {
  rm -f $out/g; /Applications/Ghostty.app/Contents/MacOS/ghostty --version | head -1
  open -na Ghostty.app --args -e /bin/zsh -l "$(r "print -r -- ok-{number} > $out/g" x)"; wait_for $out/g ghostty
}
terminal() {
  rm -f $out/t
  osascript -e 'on run argv' -e 'tell application "Terminal" to do script "/bin/zsh -l " & quoted form of (item 1 of argv)' \
    -e 'end run' "$(r "print -r -- ok-{number} > $out/t; exit" x)"; wait_for $out/t terminal
}
case ${1:-all} in all) inject; ghostty; terminal;; *) $1;; esac
