# Install Guide

How to install the upstream `opencode` musl build on Termux / Android (`aarch64`) with [`install.sh`](../install.sh).

- **New to this project?** Start with the [README](../README.md#install).
- **Slow or flaky connection?** Jump to [Manual download + offline install](#manual-download--offline-install).

## Contents

- [Quick install](#quick-install)
- [What gets downloaded](#what-gets-downloaded)
- [What the script does](#what-the-script-does)
- [Manual download + offline install](#manual-download--offline-install)
- [Environment variables](#environment-variables)
- [Verify](#verify)
- [Troubleshooting](#troubleshooting)

## Quick install

On Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/master/install.sh | sh
```

Pin a version instead of `latest`:

```sh
curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/master/install.sh | OPENCODE_VERSION=v1.18.32 sh
```

Or after cloning:

```sh
./install.sh
OPENCODE_VERSION=v1.18.32 ./install.sh
```

Re-running is safe — it re-downloads and re-installs.

> The ~62 MB download shows a progress bar. On mobile data expect
> 1–5 minutes. If the connection drops, use the
> [manual download flow](#manual-download--offline-install) with resume.

## What gets downloaded?

About **~64 MB total** (measured for `opencode v1.18.32` + Alpine `v3.24`):

| What | File | Size |
|---|---|---|
| `opencode` upstream binary | `opencode-linux-arm64-musl.tar.gz` | ~62.5 MB (98% of total) |
| musl loader | `musl-*.apk` | ~408 KB |
| C++ runtime | `libstdc++-*.apk` | ~888 KB |
| gcc runtime | `libgcc-*.apk` | ~65 KB |
| DNS shim + proxy | `scripts/libresolvefix.c` + `scripts/proxy.py` | ~10 KB |

GitHub API + Alpine index lookups are only a few KB.

No extra `pkg install` traffic if `clang`, `patchelf`, and `python3` are
already installed — check with:

```sh
command -v clang patchelf python3
```

If missing, the script installs `clang` + `patchelf` via `pkg`
(note: `clang` alone is hundreds of MB).

## What the script does

1. Resolves the `opencode` tag (`latest` via the GitHub API, or the pinned `OPENCODE_VERSION`).
2. Resolves the newest Alpine release and picks the matching `musl`, `libstdc++`, `libgcc` `.apk` files for `aarch64`.
3. Downloads the tarball + 3 `.apk` files with a progress bar.
4. Extracts the musl loader + libs into `$PREFIX/lib`, builds `libresolvefix.so`, installs `proxy.py` + the binary into `$PREFIX/libexec/opencode`, patches the ELF interpreter with `patchelf`, and installs the `$PREFIX/bin/opencode` wrapper.

## Manual download + offline install

Use this when the connection drops mid-download, or when you want to
download once (e.g. on a PC) and copy the files over via USB / `scp` /
Telegram saved messages.

### 1. Download the big tarball yourself (progress + resume)

> **Note:** `v1.18.32` below is an example. Check `install.sh` output or [upstream releases](https://github.com/anomalyco/opencode/releases) for the current version tag.

```sh
OPENCODE_VERSION=v1.18.32
curl -L -C - --progress-bar \
  -o opencode-linux-arm64-musl.tar.gz \
  "https://github.com/anomalyco/opencode/releases/download/$OPENCODE_VERSION/opencode-linux-arm64-musl.tar.gz"

ls -lh opencode-linux-arm64-musl.tar.gz
# expected ~62M. If it stops, re-run the same command — `-C -` resumes.
```

Copy the file to your phone if you downloaded it elsewhere.

### 2. Feed it to the installer (skips download)

```sh
OPENCODE_VERSION=v1.18.32 \
OPENCODE_TARBALL_PATH=./opencode-linux-arm64-musl.tar.gz \
./install.sh
```

The script prints `Using local tarball: ... (skipping download)` and
copies it instead of running `curl`.

### 3. Same for the Alpine `.apk` files (optional, ~1.4 MB total)

Normally not needed, but useful for a fully offline install:

```sh
# Example for Alpine v3.24 — check install.sh output for current names:
BASE=https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64
curl -LO "$BASE/musl-1.2.6-r2.apk" \
     -LO "$BASE/libstdc++-15.2.0-r5.apk" \
     -LO "$BASE/libgcc-15.2.0-r5.apk"

MUSL_PKG_PATH=./musl-1.2.6-r2.apk \
LIBSTDC_PKG_PATH=./libstdc++-15.2.0-r5.apk \
LIBGCC_PKG_PATH=./libgcc-15.2.0-r5.apk \
./install.sh
```

Fully offline example:

```sh
OPENCODE_VERSION=v1.18.32 \
OPENCODE_TARBALL_PATH=./opencode-linux-arm64-musl.tar.gz \
MUSL_PKG_PATH=./musl-1.2.6-r2.apk \
LIBSTDC_PKG_PATH=./libstdc++-15.2.0-r5.apk \
LIBGCC_PKG_PATH=./libgcc-15.2.0-r5.apk \
./install.sh
```

## Environment variables

All optional. File paths must point to existing files.

| Variable | Purpose | Default |
|---|---|---|
| `OPENCODE_TARBALL_PATH` | Use a pre-downloaded `opencode-linux-arm64-musl.tar.gz` | (download) |
| `MUSL_PKG_PATH` | Use a pre-downloaded `musl-*.apk` | (download) |
| `LIBSTDC_PKG_PATH` | Use a pre-downloaded `libstdc++-*.apk` | (download) |
| `LIBGCC_PKG_PATH` | Use a pre-downloaded `libgcc-*.apk` | (download) |
| `OPENCODE_VERSION` | Pin version (`vX.Y.Z`) instead of `latest` | `latest` |
| `REPO` | Upstream GitHub repo | `anomalyco/opencode` |
| `INSTALL_NAME` | Binary name installed in `$PREFIX/bin` | `opencode` |

## Verify

```sh
opencode --version
ls -lh "$PREFIX/lib/ld-musl-aarch64.so.1" \
       "$PREFIX/lib/libstdc++.so.6" \
       "$PREFIX/lib/libgcc_s.so.1" \
       "$PREFIX/lib/libresolvefix.so" \
       "$PREFIX/libexec/opencode/opencode-musl.bin" \
       "$PREFIX/libexec/opencode/proxy.py" \
       "$PREFIX/bin/opencode"
```

Tip: to watch download progress from a second Termux session:

```sh
watch -n1 'ls -lh ~/tmp/opencode-musl-install.*/'
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not resolve latest version` | GitHub API blocked / rate-limited. Pin a version: `OPENCODE_VERSION=v1.18.32 ./install.sh`. |
| `Download failed` mid-way | Re-run, or use the [manual download flow](#manual-download--offline-install) with `curl -C -` resume. |
| `Only aarch64 is supported` | `uname -m` must print `aarch64` (upstream ships no `armv7` musl build). |
| `clang` / `patchelf` missing | The script runs `pkg install -y clang patchelf` automatically (extra download, 100s of MB for `clang`). |
| No progress bar / looks stuck | You have the old script — pull the latest `install.sh` (progress-bar + `OPENCODE_TARBALL_PATH` support). |

See also: [`install.sh`](../install.sh) header comments and the
[Requirements](../README.md#requirements) section in the README.
