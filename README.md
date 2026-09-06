# opencode-termux-musl

Run the **upstream [opencode](https://github.com/anomalyco/opencode) CLI** on Termux / Android (aarch64) by reusing its official musl-linked ARM64 binary.

This is an alternative to [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux), which cross-compiles Bun from source for Android and is pinned to opencode 1.17.9. This project avoids that build entirely.

## Why

opencode is a Bun standalone binary. The Bun team has [closed Android support as "not planned"](https://github.com/oven-sh/bun/issues/9), so running opencode on Termux normally requires:

1. Cross-compiling Bun v1.2.13 for Android/aarch64 (~30 min CMake build)
2. Cross-compiling WebKit/JavaScriptCore (~90 min)
3. Cross-compiling ICU, TinyCC, OpenTUI
4. Splicing the host-built opencode module graph onto the Android Bun binary
5. Patching the bionic heap-tagging ABI for JSC

That's a 6-stage CI pipeline. It works, but it's a maintenance burden and the maintainer of guysoft/opencode-termux has not published a release since opencode 1.17.9 (June 2026), even though upstream has shipped 11+ versions since then.

The much simpler approach: take upstream's `opencode-linux-arm64-musl.tar.gz`, supply a musl dynamic linker + musl-compiled libstdc++/libgcc_s from Alpine, patch the interpreter, done.

## Install

On Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/main/install.sh | sh
```

After it finishes, the wrapper prints the installed opencode version (whatever upstream's current release is).

Then run:

```sh
opencode --version
opencode
```

## How it works

The upstream binary is dynamically linked. Its ELF interpreter points at `/lib/ld-musl-aarch64.so.1`, which Termux doesn't ship. The installer:

1. Downloads the latest upstream `opencode-linux-arm64-musl.tar.gz`.
2. Downloads Alpine's musl package (provides `ld-musl-aarch64.so.1`) and musl-compiled `libstdc++` / `libgcc_s`.
3. Installs them to `$PREFIX/lib`.
4. Uses `patchelf` to retarget the binary's interpreter to the installed musl loader.
5. Installs a wrapper that:
   - clears any stale `LD_PRELOAD` from the previous (guysoft) wrapper — that shim references glibc-only symbols (`__register_atfork`, `__errno`, `__strlen_chk`, etc.) that don't exist in musl;
   - sets the env vars opencode needs on Android: `TERM` for the TUI, `OPENCODE_DISABLE_TUI_AUDIO=1`, `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true`;
   - runs the binary against the musl loader in `$PREFIX/lib`.

## Why no `libtagfix.so` shim

The other Termux build ([guysoft/opencode-termux](https://github.com/guysoft/opencode-termux)) ships an `LD_PRELOAD` shim that calls `mallopt()` to disable Android's bionic heap-pointer tagging. That build is Bionic-linked, so its allocator is bionic's — and bionic's allocator tags heap pointers with the top byte, which JSC's NaN-boxing clobbers, causing a `Pointer tag ... was truncated` abort on `free()`.

This build is **musl-linked**. opencode's allocations go through musl's allocator, which does not tag pointers. The shim is therefore unnecessary here, and shipping a Bionic-targeted `.so` under a musl process would either fail to load (different libc resolution) or cause a libc-mismatch corruption. If you do hit a "Pointer tag" crash, the cause is different (e.g. kernel-level tagged-address enforcement on `ioctl`/`prctl` from a JSC path) and would need to be fixed in JSC's syscall wrappers upstream, not in userspace.

## What's not working

Known limitations:

- **File watcher**: `@parcel/watcher`'s native binding is x86_64-only; this build has the same issue. Disabled in the wrapper via `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true`.
- **TUI audio**: explicitly disabled in the wrapper (`OPENCODE_DISABLE_TUI_AUDIO=1`) since OpenTUI's audio backend isn't useful on Android.
- **PTY support**: depends on `librust_pty_arm64.so`. The guysoft build ships this; we don't yet. PRs welcome.

## Requirements

- Termux (Android 7.0+ / API 24+, aarch64)
- `curl`, `tar`, `patchelf` (installer will install `patchelf` automatically if missing)
- Internet access to `github.com` and `dl-cdn.alpinelinux.org`

## Tested on

- Pixel 10 (Android 17, Termux 0.119, aarch64) — installer completes, wrapper prints upstream's version string. TUI hasn't been re-tested since the install URL was filled in; reports welcome.

## Verifying an install

A non-interactive smoke test is included at `scripts/smoke-test.sh`. It
runs `install.sh` into a throwaway `$PREFIX`, then verifies the binary's
ELF interpreter, `DT_NEEDED` resolution, and `--version`:

```sh
./scripts/smoke-test.sh
```

## Capturing screenshots

`scripts/capture-screenshots.sh` drives the full install + TUI demo and
saves PNGs into `docs/screenshots/`. **Run it from the Termux app
directly** (not from opencode or another agent) so that `screencap`
captures the terminal:

```sh
./scripts/capture-screenshots.sh
```

It produces:

- `00-clean-terminal.png`
- `01-install-complete.png`
- `02-version-check.png`
- `03-installed-files.png`
- `04-elf-interpreter.png`
- `05-opencode-tui.png`

## Credits

- [opencode](https://github.com/anomalyco/opencode) by Anomaly
- [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) for the original Android patches and the Bionic compatibility shims that informed this work
- [Alpine Linux](https://alpinelinux.org/) for the musl libc + libstdc++/libgcc_s packages

## License

MIT
