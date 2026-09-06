#!/bin/sh
# smoke-test.sh — verify a fresh install of opencode-termux-musl works.
#
# Runs install.sh into a temporary PREFIX, then checks:
#   - all expected files exist in the right places
#   - the opencode binary's interpreter points at our musl loader
#   - all DT_NEEDED entries can be resolved against our $PREFIX/lib
#   - `opencode --version` returns a sensible semver string
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Exit status: 0 on success, 1 on any failed check. Network is required.

set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/opencode-smoke.$$"
export PREFIX="$WORK/prefix"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }
note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$WORK" "$PREFIX"
trap 'rm -rf "$WORK"' EXIT

note "Running install.sh into $PREFIX ..."
sh "$REPO_DIR/install.sh" >/dev/null

note "Checking installed files..."
[ -x "$PREFIX/bin/opencode" ]                             || fail "wrapper missing"
[ -x "$PREFIX/libexec/opencode/opencode-musl.bin" ]        || fail "binary missing"
[ -x "$PREFIX/lib/ld-musl-aarch64.so.1" ]                 || fail "musl loader missing"
[ -x "$PREFIX/lib/libgcc_s.so.1" ]                        || fail "libgcc_s missing"
[ -e "$PREFIX/lib/libstdc++.so.6" ]                       || fail "libstdc++ symlink missing"
[ -e "$(readlink -f "$PREFIX/lib/libstdc++.so.6")" ]      || fail "libstdc++ symlink target missing"
pass "files in place"

note "Checking ELF interpreter..."
INTERP=$(readelf -l "$PREFIX/libexec/opencode/opencode-musl.bin" 2>/dev/null \
         | sed -n 's/.*program interpreter: *\(\[[^]]*\]\|\S*\).*/\1/p' \
         | head -1 | tr -d '[]')
[ "$INTERP" = "$PREFIX/lib/ld-musl-aarch64.so.1" ] \
  || fail "interpreter is '$INTERP', expected '$PREFIX/lib/ld-musl-aarch64.so.1'"
pass "interpreter = $INTERP"

note "Checking DT_NEEDED entries resolve..."
NEEDED=$(readelf -d "$PREFIX/libexec/opencode/opencode-musl.bin" 2>/dev/null \
         | sed -n 's/.*NEEDED.*\[\(.*\)\].*/\1/p')
for lib in $NEEDED; do
  case "$lib" in
    libc.musl-*|ld-musl-*) target="$PREFIX/lib/ld-musl-aarch64.so.1" ;;
    libgcc_s.so.1)          target="$PREFIX/lib/libgcc_s.so.1" ;;
    libstdc++.so.6)         target="$PREFIX/lib/libstdc++.so.6" ;;
    *)                      target="" ;;
  esac
  [ -n "$target" ] || fail "unknown DT_NEEDED entry: $lib"
  [ -e "$target" ] || fail "$lib -> $target (missing)"
  pass "$lib -> $target"
done

note "Running opencode --version ..."
VERSION=$(PATH="$PREFIX/bin:$PATH" TERMUX_VERSION=test PREFIX="$PREFIX" \
          HOME="$WORK" sh "$PREFIX/bin/opencode" --version 2>&1)
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' \
  || fail "unexpected --version output: $VERSION"
pass "version = $VERSION"

note "All checks passed."
