#!/bin/sh
# check-update.sh — check for a newer upstream opencode release.
#
# Compares the installed `opencode --version` against the latest
# upstream tag (GitHub API, a few KB). By default it only checks and
# notifies — it never downloads anything unless you pass --yes.
#
# Usage:
#   ./check-update.sh           # check only, notify if behind (exit 2)
#   ./check-update.sh --yes     # check and re-run install.sh if behind
#
# Exit codes: 0 = up to date, 1 = error, 2 = update available.
#
# Unattended daily check (needs the Termux:API app):
#   termux-job-scheduler --job-id 7801 --period-ms 86400000 \
#     --network unmetered --persisted true \
#     -s /path/to/opencode-termux-musl/scripts/check-update.sh
#
# Requires: curl (opencode binary for the installed version).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-anomalyco/opencode}"
APPLY=0

for arg in "$@"; do
  case "$arg" in
    --yes) APPLY=1 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 1 ;;
  esac
done

notify() {
  if command -v termux-notification >/dev/null 2>&1; then
    termux-notification --title "opencode update" --content "$1" 2>/dev/null || true
  fi
}

installed="$(opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$installed" ] || { echo "Could not read installed opencode version." >&2; exit 1; }

if command -v jq >/dev/null 2>&1; then
  latest="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')"
else
  latest="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep -oE '"tag_name": *"v?[^"]+"' | head -1 | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+')"
fi
[ -n "$latest" ] || { echo "Could not resolve latest upstream version (network/API issue?)." >&2; exit 1; }
latest="${latest#v}"

if [ "$installed" = "$latest" ]; then
  echo "opencode is up to date ($installed)."
  exit 0
fi

echo "Update available: installed $installed, latest $latest."
notify "opencode $installed -> $latest available. Re-run install.sh to update."

if [ "$APPLY" -eq 1 ]; then
  if [ -x "$SCRIPT_DIR/../install.sh" ]; then
    echo "Applying update via install.sh..."
    exec "$SCRIPT_DIR/../install.sh"
  else
    echo "Cannot auto-apply: install.sh not found next to this script." >&2
    echo "Update manually: curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/master/install.sh | sh" >&2
    exit 2
  fi
fi

exit 2
