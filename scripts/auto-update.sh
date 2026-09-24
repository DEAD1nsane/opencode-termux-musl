#!/data/data/com.termux/files/usr/bin/sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/check-update.sh" --yes
