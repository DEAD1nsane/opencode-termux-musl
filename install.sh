#!/bin/sh
# install.sh — install opencode (upstream musl build) on Termux/Android
#
# Downloads the latest upstream opencode release (musl-linked, aarch64),
# extracts the musl dynamic linker + libstdc++/libgcc_s from Alpine,
# patches the binary's interpreter, and installs everything under $PREFIX.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/opencode-termux-musl/main/install.sh | sh
# Or after cloning:
#   ./install.sh
#
# Re-running is safe: it always re-downloads the latest upstream release.
#
# Requires: curl, tar (Termux has both by default).

set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$HOME/tmp}"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
REPO="${REPO:-anomalyco/opencode}"
INSTALL_NAME="${INSTALL_NAME:-opencode}"

WORK="$TMPDIR/opencode-musl-install.$$"
mkdir -p "$WORK" "$TMPDIR"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Pick Termux arch (must be aarch64 — opencode upstream has no armv7 build).
ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || die "Only aarch64 is supported (got: $ARCH)."

# Resolve latest version if requested.
if [ "$OPENCODE_VERSION" = "latest" ]; then
  log "Resolving latest opencode version..."
  OPENCODE_VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  [ -n "$OPENCODE_VERSION" ] || die "Could not resolve latest version."
fi
log "Installing opencode $OPENCODE_VERSION"

# Pick a working Alpine mirror.
ALPINE_BASE="https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64"
MUSL_PKG="musl-1.2.5-r11.apk"
LIBSTDC_PKG="libstdc++-14.2.0-r4.apk"
LIBGCC_PKG="libgcc-14.2.0-r4.apk"

# Download upstream binary.
log "Downloading upstream musl binary..."
TARBALL="opencode-linux-arm64-musl.tar.gz"
URL="https://github.com/$REPO/releases/download/$OPENCODE_VERSION/$TARBALL"
curl -fsSL -o "$WORK/$TARBALL" "$URL" || die "Download failed: $URL"

# Download Alpine musl + C++ libs.
log "Downloading musl libc + libstdc++/libgcc_s from Alpine..."
curl -fsSL -o "$WORK/$MUSL_PKG"      "$ALPINE_BASE/$MUSL_PKG"      || die "musl download failed"
curl -fsSL -o "$WORK/$LIBSTDC_PKG"   "$ALPINE_BASE/$LIBSTDC_PKG"   || die "libstdc++ download failed"
curl -fsSL -o "$WORK/$LIBGCC_PKG"    "$ALPINE_BASE/$LIBGCC_PKG"    || die "libgcc download failed"

# Extract everything.
log "Extracting..."
cd "$WORK"
tar -xzf "$TARBALL" || die "Failed to extract tarball"
mkdir -p musl-libs
(cd musl-libs && tar -xzf "../$MUSL_PKG"    2>/dev/null && \
                 tar -xzf "../$LIBSTDC_PKG" 2>/dev/null && \
                 tar -xzf "../$LIBGCC_PKG"  2>/dev/null)

[ -f opencode ] || die "Tarball did not contain 'opencode' binary."

# Install musl loader + libs into $PREFIX/lib.
log "Installing musl libs to $PREFIX/lib..."
install -d "$PREFIX/lib"
install -m 755 musl-libs/lib/ld-musl-aarch64.so.1           "$PREFIX/lib/"
install -m 755 musl-libs/usr/lib/libgcc_s.so.1              "$PREFIX/lib/"
install -m 755 musl-libs/usr/lib/libstdc++.so.6.0.33        "$PREFIX/lib/"
ln -sf libstdc++.so.6.0.33 "$PREFIX/lib/libstdc++.so.6"

# Install the opencode binary into $PREFIX/libexec.
log "Installing opencode binary..."
install -d "$PREFIX/libexec/opencode"
install -m 755 opencode "$PREFIX/libexec/opencode/opencode-musl.bin"

# Patch the interpreter to point at the installed musl loader.
# patchelf is provided by the 'patchelf' Termux package.
if ! command -v patchelf >/dev/null 2>&1; then
  warn "patchelf not found; attempting Termux install..."
  pkg install -y patchelf || die "Please install patchelf: pkg install patchelf"
fi
patchelf --set-interpreter "$PREFIX/lib/ld-musl-aarch64.so.1" \
  "$PREFIX/libexec/opencode/opencode-musl.bin"

# Install wrapper script.
log "Installing wrapper script..."
install -d "$PREFIX/bin"
cat > "$PREFIX/bin/$INSTALL_NAME" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# opencode wrapper for the upstream musl-linked build.
# Clears the glibc LD_PRELOAD shims from older wrappers; they reference
# glibc-only symbols (__register_atfork, __errno, etc.) that don't exist
# in musl.
exec env -i \
  HOME="$HOME" \
  PATH="$PATH" \
  PREFIX="$PREFIX" \
  TERM="${TERM:-xterm-256color}" \
  LANG="${LANG:-en_US.UTF-8}" \
  TMPDIR="${TMPDIR:-$HOME/tmp}" \
  TEMP="${TMPDIR:-$HOME/tmp}" \
  TMP="${TMPDIR:-$HOME/tmp}" \
  TERMUX_VERSION="$TERMUX_VERSION" \
  ANDROID_ROOT="${ANDROID_ROOT:-/system}" \
  LD_LIBRARY_PATH="$PREFIX/lib" \
  OPENCODE_DISABLE_TUI_AUDIO=1 \
  OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true \
  "$PREFIX/libexec/opencode/opencode-musl.bin" "$@"
EOF
chmod +x "$PREFIX/bin/$INSTALL_NAME"

log "Done. Try: $INSTALL_NAME --version"
"$PREFIX/bin/$INSTALL_NAME" --version
