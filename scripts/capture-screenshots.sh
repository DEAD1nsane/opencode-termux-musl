#!/bin/sh
# capture-screenshots.sh — drive the install + TUI demo and screenshot
# each step into docs/screenshots/.
#
# IMPORTANT: run this from the Termux app directly, NOT from opencode
# or any other agent. The script calls `screencap` to capture whatever
# is on the device's screen, so the Termux terminal must be the
# foreground app while the script runs.
#
# It uses Termux's storage permission to drop the PNGs into
# /sdcard/Pictures/, then moves them into the repo.
#
# Prerequisites:
#   - Termux is the foreground app
#   - Storage permission granted: `termux-setup-storage`
#   - The repo is cloned to ~/opencode-termux-musl
#
# Usage:
#   ./scripts/capture-screenshots.sh

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHOT_DIR="$REPO_DIR/docs/screenshots"
TMP_DIR="/sdcard/Pictures/opencode-shots.$$"
mkdir -p "$SHOT_DIR" "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }

capture() {
  name="$1"; shift
  out="$TMP_DIR/$name"
  /system/bin/screencap -p "$out" || { warn "screencap failed"; return 1; }
  echo "$out"
}

clear; sleep 0.5

note "Step 1: capture clean terminal"
clear; sleep 1
capture 00-clean-terminal.png

note "Step 2: run installer (visible output)"
# Re-running is safe. Use the local install.sh if we're in the repo,
# otherwise fetch from GitHub.
if [ -x "$REPO_DIR/install.sh" ]; then
  sh "$REPO_DIR/install.sh"
else
  curl -fsSL "https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/main/install.sh" | sh
fi
capture 01-install-complete.png

note "Step 3: opencode --version"
clear
echo '$ opencode --version'
if command -v opencode >/dev/null 2>&1; then
  opencode --version
  echo
  echo '$ which opencode'
  which opencode
else
  echo 'opencode: command not found (install step failed?)'
fi
sleep 0.5
capture 02-version-check.png

note "Step 4: installed files"
clear
echo '$ ls -la $PREFIX/lib/ld-musl* $PREFIX/lib/libstdc++* $PREFIX/lib/libgcc*'
ls -la "$PREFIX/lib/ld-musl"* "$PREFIX/lib/libstdc++"* "$PREFIX/lib/libgcc"* 2>&1
sleep 0.5
capture 03-installed-files.png

note "Step 5: ELF interpreter + NEEDED"
clear
BIN="$PREFIX/libexec/opencode/opencode-musl.bin"
echo "\$ readelf -l $BIN | grep -A1 INTERP"
readelf -l "$BIN" 2>/dev/null | grep -A1 INTERP
echo
echo "\$ readelf -d $BIN | grep NEEDED"
readelf -d "$BIN" 2>/dev/null | grep NEEDED
sleep 0.5
capture 04-elf-interpreter.png

note "Step 6: launching opencode TUI"
clear
echo '$ opencode'
echo
echo 'opencode will launch. Let the TUI render, then press "q"'
echo 'inside opencode to quit. The script will capture the TUI'
echo 'before the quit and continue.'
echo
sleep 2
# Launch in the background, capture mid-render, then signal-quit it.
# opencode responds to SIGINT (Ctrl-C) by exiting cleanly; if it
# doesn't, escalate to SIGTERM then SIGKILL.
( opencode >/dev/null 2>&1 ) &
OPENCODE_PID=$!
sleep 5
capture 05-opencode-tui.png
kill -INT $OPENCODE_PID 2>/dev/null || true
sleep 1
kill -TERM $OPENCODE_PID 2>/dev/null || true
sleep 1
kill -KILL $OPENCODE_PID 2>/dev/null || true
wait $OPENCODE_PID 2>/dev/null || true
sleep 1
clear
echo "TUI demo finished."

note "Step 7: moving screenshots into repo"
mv "$TMP_DIR"/*.png "$SHOT_DIR/"
rmdir "$TMP_DIR"

note "Done. Screenshots in $SHOT_DIR:"
ls -la "$SHOT_DIR"
