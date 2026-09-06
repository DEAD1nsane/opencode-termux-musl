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
curl -fsSL https://raw.githubusercontent.com/<owner>/opencode-termux-musl/main/install.sh | sh
```

After it finishes, you should see:

```
1.18.29
```

(Or whatever the current upstream version is.)

Then run:

```sh
opencode --version
opencode
```

## How it works

The upstream binary is dynamically linked. Its ELF interpreter points at `/lib/ld-musl-aarch64.so.1`, which Termux doesn't ship. The installer:

1. Downloads the latest upstream `opencode-linux-arm64-musl.tar.gz`
2. Downloads Alpine's musl package (provides `ld-musl-aarch64.so.1`)
3. Downloads Alpine's musl-compiled `libstdc++` and `libgcc_s`
4. Installs them to `$PREFIX/lib`
5. Uses `patchelf` to retarget the binary's interpreter to the installed musl loader
6. Installs a wrapper that clears the glibc `LD_PRELOAD` shims set by the old guysoft wrapper (those reference glibc-only symbols like `__register_atfork`, `__errno`, `__strlen_chk`, etc. that don't exist in musl)

## What's not working

Things that haven't been tested or are known broken:

- **File watcher**: `@parcel/watcher`'s native binding is x86_64-only; this build has the same issue. Already mitigated upstream via `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true`.
- **TUI audio**: explicitly disabled in the wrapper (`OPENCODE_DISABLE_TUI_AUDIO=1`) since OpenTUI's audio backend isn't useful on Android.
- **PTY support**: depends on `librust_pty_arm64.so`. The guysoft build ships this; we don't yet. PRs welcome.
- **Pointer-tag SIGABRT**: opencode's TUI hits Android's "Pointer tag ... was truncated" abort because JSC's NaN-boxing clears the 0xB4 heap-pointer tag. The guysoft build works around this with `libtagfix.so` (LD_PRELOAD'd `mallopt` shim). We don't yet. If you see this crash on startup, see `scripts/libtagfix.c` (TODO).

## Requirements

- Termux (Android 7.0+ / API 24+, aarch64)
- `curl`, `tar`, `patchelf` (installer will install `patchelf` automatically if missing)
- Internet access to `github.com` and `dl-cdn.alpinelinux.org`

## Tested on

- Pixel 8 (Android 16, Termux, aarch64) — full TUI working

## Credits

- [opencode](https://github.com/anomalyco/opencode) by Anomaly
- [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) for the original Android patches and the Bionic compatibility shims that informed this work
- [Alpine Linux](https://alpinelinux.org/) for the musl libc + libstdc++/libgcc_s packages

## License

MIT
