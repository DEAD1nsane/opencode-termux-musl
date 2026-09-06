#!/bin/sh
# capture-screenshots.sh — guide the user through each screenshot step.
#
# Run this from the Termux app directly (not from opencode).
# For each step, the script prints what to run, then tells you to
# take a screenshot with Volume Down + Power. After you take the
# screenshot, press Enter and the script renames the last screenshot
# into the right filename under docs/screenshots/.
#
# Prerequisites:
#   - Termux is the foreground app
#   - Storage permission granted: `termux-setup-storage`
#   - The repo is cloned to ~/opencode-termux-musl

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHOT_DIR="$REPO_DIR/docs/screenshots"
mkdir -p "$SHOT_DIR"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
prompt() { printf '\033[1;33m>>> %s\033[0m\n' "$*"; }

# Find the most recent .png in /sdcard/Pictures/ (Android's default
# screenshot directory). This is what Volume Down + Power saves to.
latest_screenshot() {
  ls -t /sdcard/Pictures/*.png 2>/dev/null | head -1
}

# Print a command, tell the user to screenshot it, wait for Enter,
# then copy the last screenshot into $SHOT_DIR as the given name.
capture() {
  name="$1"; shift
  echo
  prompt "Do this:"
  echo "  $*"
  echo
  prompt "Take a screenshot now (Volume Down + Power), then press Enter."
  read -r _
  src=$(latest_screenshot)
  if [ -n "$src" ]; then
    cp "$src" "$SHOT_DIR/$name"
    echo "  -> saved: docs/screenshots/$name"
  else
    prompt "No .png found in /sdcard/Pictures/. Did you grant storage permission?"
    prompt "Run: termux-setup-storage"
  fi
}

clear
note "Step 1/7: Clean terminal"
capture 00-clean-terminal.png clear

note "Step 2/7: Install opencode"
if [ -x "$REPO_DIR/install.sh" ]; then
  sh "$REPO_DIR/install.sh"
else
  curl -fsSL "https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/main/install.sh" | sh
fi
capture 01-install-complete.png echo

note "Step 3/7: opencode --version"
echo '$ opencode --version'
opencode --version
echo
echo '$ which opencode'
which opencode
capture 02-version-check.png echo

note "Step 4/7: Installed files"
echo '$ ls -la $PREFIX/lib/ld-musl* $PREFIX/lib/libstdc++* $PREFIX/lib/libgcc*'
ls -la "$PREFIX/lib/ld-musl"* "$PREFIX/lib/libstdc++"* "$PREFIX/lib/libgcc"* 2>&1
capture 03-installed-files.png echo

note "Step 5/7: ELF interpreter + DT_NEEDED"
echo '$ readelf -l $PREFIX/libexec/opencode/opencode-musl.bin | grep -A1 INTERP'
readelf -l "$PREFIX/libexec/opencode/opencode-musl.bin" 2>/dev/null | grep -A1 INTERP
echo
echo '$ readelf -d $PREFIX/libexec/opencode/opencode-musl.bin | grep NEEDED'
readelf -d "$PREFIX/libexec/opencode/opencode-musl.bin" 2>/dev/null | grep NEEDED
capture 04-elf-interpreter.png echo

note "Step 6/7: opencode TUI"
echo '$ opencode'
echo
prompt "opencode will launch. Let it render, then take a screenshot."
prompt "After the screenshot, press 'q' inside opencode to quit."
opencode
capture 05-opencode-tui.png echo

note "Step 7/7: Done"
echo
echo "Screenshots saved to docs/screenshots/:"
ls -la "$SHOT_DIR"
