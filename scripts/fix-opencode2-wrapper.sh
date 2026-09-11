#!/bin/sh
# fix-opencode2-wrapper.sh — fix the broken opencode2 wrapper on Termux/Android
#
# The npm-installed opencode2 wrapper has a recursive self-call bug:
# it execs itself instead of opencode2.exe, causing infinite recursion.
# It also unnecessarily starts the Python proxy (v2 is Node.js-based
# and doesn't need the Bun io_uring proxy workaround).
#
# Additionally, the npm-installed binary's ELF interpreter points at
# /lib/ld-musl-aarch64.so.1, but Termux installs the musl loader at
# $PREFIX/lib/. This script patches the interpreter with patchelf.
#
# This script creates a correct wrapper at $PREFIX/bin/opencode2.
#
# Usage:
#   ./scripts/fix-opencode2-wrapper.sh
# Or after cloning:
#   curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/master/scripts/fix-opencode2-wrapper.sh | sh
#
# Requires: the npm package @opencode-ai/cli to be installed globally,
#           patchelf (installed automatically if missing).

set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Find the opencode2.exe binary.
V2_BIN="$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe"
[ -f "$V2_BIN" ] || die "opencode2 binary not found at $V2_BIN"

# Check if it's actually an ELF binary or just the npm postinstall placeholder.
V2_MAGIC=$(head -c 4 "$V2_BIN" 2>/dev/null | od -A n -t x1 | tr -d ' ')
if [ "$V2_MAGIC" != "7f454c46" ]; then
  warn "opencode2.exe is not a real binary (postinstall placeholder)."
  warn "Installing the musl binary package..."
  npm install -g --force --ignore-scripts @opencode-ai/cli-linux-arm64-musl 2>/dev/null \
    || npm install -g --force --ignore-scripts @opencode-ai/cli-linux-arm64 2>/dev/null \
    || die "Could not install musl binary. Try: npm install -g --force --ignore-scripts @opencode-ai/cli-linux-arm64-musl"
  MUSL_BIN=$(npm root -g)/@opencode-ai/cli-linux-arm64-musl/bin/opencode2
  [ -f "$MUSL_BIN" ] || MUSL_BIN=$(npm root -g)/@opencode-ai/cli-linux-arm64/bin/opencode2
  [ -f "$MUSL_BIN" ] || die "Musl binary not found after install."
  cp "$MUSL_BIN" "$V2_BIN"
  log "Installed musl binary from npm package."
fi

log "Found opencode2 binary: $V2_BIN"

# Patch the ELF interpreter to point at the installed musl loader.
# The npm binary expects /lib/ld-musl-aarch64.so.1 but Termux installs
# it at $PREFIX/lib/ld-musl-aarch64.so.1.
MUSL_LOADER="$PREFIX/lib/ld-musl-aarch64.so.1"
if [ -f "$MUSL_LOADER" ]; then
  CURRENT_INTERP=$(readelf -l "$V2_BIN" 2>/dev/null | sed -n 's/.*program interpreter: \(.*\)/\1/p')
  if [ "$CURRENT_INTERP" != "$MUSL_LOADER" ]; then
    if ! command -v patchelf >/dev/null 2>&1; then
      warn "patchelf not found; attempting Termux install..."
      pkg install -y patchelf || die "Please install patchelf: pkg install patchelf"
    fi
    log "Patching ELF interpreter to $MUSL_LOADER..."
    patchelf --set-interpreter "$MUSL_LOADER" "$V2_BIN"
  else
    log "ELF interpreter already correct."
  fi
else
  warn "Musl loader not found at $MUSL_LOADER — skipping interpreter patch."
  warn "You may need to run install.sh first to install the musl loader."
fi

# Create the wrapper script.
log "Creating opencode2 wrapper at $PREFIX/bin/opencode2..."
install -d "$PREFIX/bin"
# Remove any symlink that npm may have created (points to the ELF binary).
[ -L "$PREFIX/bin/opencode2" ] && rm "$PREFIX/bin/opencode2"
cat > "$PREFIX/bin/opencode2" <<'WRAPPER'
#!/data/data/com.termux/files/usr/bin/sh
# opencode2 wrapper for the upstream musl-linked build (v2 / Node.js).
#
# v2 is Node.js-based and does NOT need the Python HTTP proxy that v1
# (Bun-based) requires. This wrapper only sets up the musl loader and
# DNS resolution shim — no proxy startup, no HTTP_PROXY env vars.
#
# NOTE: we do NOT use env -i. On Android, DNS resolution depends on
# bionic's resolver which reads system properties and Android's netd
# daemon — not env vars, but the resolver needs access to the system
# libraries that provide these. env -i strips everything and breaks
# DNS completely (curl returns "Could not resolve host"). Instead we
# set only what we need and unset what we don't.
unset LD_PRELOAD
export LD_PRELOAD="$PREFIX/lib/libresolvefix.so"
export HOME
export PATH
export PREFIX
export TERM="${TERM:-xterm-256color}"
export LANG="${LANG:-en_US.UTF-8}"
export TMPDIR="${TMPDIR:-$HOME/tmp}"
export TEMP="${TMPDIR:-$HOME/tmp}"
export TMP="${TMPDIR:-$HOME/tmp}"
export TERMUX_VERSION
export ANDROID_ROOT="${ANDROID_ROOT:-/system}"
export LD_LIBRARY_PATH="$PREFIX/lib"
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"
export NO_PROXY="localhost,127.0.0.1"
export no_proxy="localhost,127.0.0.1"
export NODE_OPTIONS="--dns-result-order=ipv4first"

exec "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe" --standalone "$@"
WRAPPER
chmod +x "$PREFIX/bin/opencode2"

log "Done. Try: opencode2 --version"
"$PREFIX/bin/opencode2" --version
