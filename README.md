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

That's a 6-stage CI pipeline. It works, but it's a maintenance burden and the maintainer of [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) has not published a release since opencode 1.17.9 (June 2026), even though upstream has shipped 11+ versions since then.

The much simpler approach: take upstream's `opencode-linux-arm64-musl.tar.gz`, supply a musl dynamic linker + musl-compiled libstdc++/libgcc_s from Alpine, patch the interpreter, done.

## Install

On Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/DEAD1nsane/opencode-termux-musl/master/install.sh | sh
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
5. Builds and installs `libresolvefix.so` — an LD_PRELOAD shim that:
   - Redirects musl's `/etc/resolv.conf` reads to Termux's copy at `$PREFIX/etc/resolv.conf`
   - Forwards `getaddrinfo()` to bionic's resolver (via `dlopen`) so DNS works through Android's `netd` daemon
6. Installs a local HTTP proxy (`proxy.py`) — Bun's io_uring-based networking doesn't work on Android, so all outbound traffic (API requests, webfetch, websearch, model registry, plugin installs, etc.) is routed through a Python proxy on `127.0.0.1:8080`
7. Installs a wrapper that:
   - Clears any stale `LD_PRELOAD` from the previous (guysoft) wrapper — that shim references glibc-only symbols (`__register_atfork`, `__errno`, `__strlen_chk`, etc.) that don't exist in musl
   - Loads `libresolvefix.so` for DNS resolution
   - Auto-starts the HTTP proxy if not running
   - Sets the env vars opencode needs on Android: `TERM` for the TUI, `OPENCODE_DISABLE_TUI_AUDIO=1`, `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true`, TLS cert paths
   - Sets `HTTP_PROXY`/`HTTPS_PROXY` so Bun routes all connections through the proxy
   - Runs the binary against the musl loader in `$PREFIX/lib`

### Why a proxy?

Bun uses [io_uring](https://kernel.dk/io_uring.pdf) for async networking (DNS, TCP, TLS) on Linux. On Android, io_uring is either unavailable or broken — all outbound connections fail with "Unable to connect". The Python proxy works because it uses standard libc sockets (bionic's `connect()`/`sendto()`) which go through Android's normal networking stack. The proxy supports three modes:

1. **Fixed-target reverse proxy** (for the opencode.ai API): requests to `127.0.0.1:8080` are forwarded to `https://opencode.ai<path>`
2. **Absolute-URL forward proxy**: when Bun sends `GET http://...` requests (because `HTTP_PROXY` is set), the proxy extracts the target URL and forwards
3. **HTTP CONNECT tunnel**: for HTTPS targets, the proxy establishes a TCP tunnel to the remote host and pipes bytes both ways

### Why `libresolvefix.so`?

Musl's resolver reads `/etc/resolv.conf` then sends raw UDP DNS queries to the nameserver. On Android, `/etc` is read-only and raw UDP to port 53 is blocked by the firewall. The shim:

1. Intercepts `open()`/`fopen()` for `/etc/resolv.conf` and redirects to Termux's copy
2. Intercepts `getaddrinfo()` and forwards to bionic's implementation (loaded via `dlopen("libc.so")`) which uses Android's `netd` daemon for proper DNS resolution

## Why no `libtagfix.so` shim

The other Termux build ([guysoft/opencode-termux](https://github.com/guysoft/opencode-termux)) ships an `LD_PRELOAD` shim that calls `mallopt()` to disable Android's bionic heap-pointer tagging. That build is Bionic-linked, so its allocator is bionic's — and bionic's allocator tags heap pointers with the top byte, which JSC's NaN-boxing clobbers, causing a `Pointer tag ... was truncated` abort on `free()`.

This build is **musl-linked**. opencode's allocations go through musl's allocator, which does not tag pointers. The shim is therefore unnecessary here, and shipping a Bionic-targeted `.so` under a musl process would either fail to load (different libc resolution) or cause a libc-mismatch corruption. If you do hit a "Pointer tag" crash, the cause is different (e.g. kernel-level tagged-address enforcement on `ioctl`/`prctl` from a JSC path) and would need to be fixed in JSC's syscall wrappers upstream, not in userspace.

## Using with local models (Ollama)

The stable version (v1) can work with local models from Ollama. The wrapper now sets `NO_PROXY=localhost,127.0.0.1` to bypass the proxy for local connections.

1. Install and start Ollama in Termux:
   ```sh
   pkg install ollama
   ollama serve &
   ollama pull llama3
   ```

2. Configure opencode to use Ollama (in `~/.config/opencode/config.json`):
   ```json
   {
     "provider": {
       "ollama": {
         "endpoint": "http://localhost:11434",
         "model": "llama3"
       }
     }
   }
   ```

3. Run opencode:
   ```sh
   opencode
   ```

**Note**: v2 (beta) doesn't need the proxy and works with Ollama out of the box.

## What's not working

Known limitations:

- **File watcher**: `@parcel/watcher`'s native binding is x86_64-only; this build has the same issue. Disabled in the wrapper via `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER=true`.
- **TUI audio**: explicitly disabled in the wrapper (`OPENCODE_DISABLE_TUI_AUDIO=1`) since OpenTUI's audio backend isn't useful on Android.
- **PTY support**: depends on `librust_pty_arm64.so`. The guysoft build ships this; we don't yet. PRs welcome.
- **Startup latency**: the Python HTTP proxy adds ~100-200ms per request. Acceptable for interactive use.

## OpenCode v2 (beta)

OpenCode v2 is a major rewrite that replaces Bun with Node.js as the JavaScript runtime.

**⚠️ v2 does NOT work natively on Termux.** Node.js's c-ares DNS resolver bypasses `libresolvefix.so` — it does raw UDP DNS that Android blocks. Sending messages fails with `getaddrinfo ETIMEOUT`. The background server also freezes without `--standalone`.

**Solution:** Run v2 in proot Ubuntu where DNS works natively.

### Install v2 (in proot Ubuntu)

```sh
# Install in proot Ubuntu (requires --ignore-scripts since npm doesn't support Android)
proot-distro login ubuntu -- bash -c \
  "npm install -g --force --ignore-scripts @opencode-ai/cli@beta && \
   npm install -g --force --ignore-scripts @opencode-ai/cli-linux-arm64@beta && \
   cp /usr/local/lib/node_modules/@opencode-ai/cli-linux-arm64/bin/opencode2 \
      /usr/local/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe && \
   chmod +x /usr/local/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe"
```

### Run v2

```sh
oc2-ubuntu          # Launch TUI (adds --standalone automatically)
oc2-ubuntu --version
oc2-ubuntu update --method npm   # Update inside proot
```

### How `oc2-ubuntu` works

The wrapper:
1. Syncs your Termux config (themes, service.json, etc.) into proot Ubuntu
2. Copies the real binary from `~/.opencode/bin/opencode` to the npm symlink target (fixes the postinstall placeholder)
3. Runs `opencode2 --standalone` inside proot Ubuntu

After `oc2-ubuntu update`, the wrapper automatically copies the real binary back so you can launch immediately.

### Update v2

```sh
oc2-ubuntu update --method npm
```

This runs `opencode2 update` inside proot Ubuntu. After it completes, the wrapper copies the real binary back. Then run `oc2-ubuntu` to launch.

**Note:** The `opencode2 update` command uses npm internally and may install to `@opencode/cli` (without `-ai`). The wrapper handles this by copying the binary to both possible locations.

### v1 vs v2

| | v1 (stable) | v2 (beta via proot) |
|---|---|---|
| Runtime | Bun | Node.js |
| Works on Termux | Yes (native) | No (needs proot Ubuntu) |
| Install method | `install.sh` | `npm install` in proot |
| Run command | `opencode` | `oc2-ubuntu` |
| Update | `install.sh` (re-run) | `oc2-ubuntu update --method npm` |
| Proxy needed | Yes (io_uring broken on Android) | No |

**Status**: v1 is stable and production-ready. v2 works via proot Ubuntu. This project remains the stable solution for v1.

## Requirements

- Termux (Android 7.0+ / API 24+, aarch64)
- `curl`, `tar`, `patchelf`, `clang` (installer will install `patchelf` and `clang` automatically if missing)
- `python3` (for the HTTP proxy — v1 only)
- Internet access to `github.com`, `dl-cdn.alpinelinux.org`, and `opencode.ai`

## Tested on

- Pixel 10 (Android 17, Termux 0.119, aarch64) — installer completes, wrapper prints upstream's version string, TUI launches and connects to API through the proxy.
- v2 (`opencode2 v0.0.0-beta-19425`) runs in proot Ubuntu using `oc2-ubuntu`.

<details>
<summary><strong>Screenshots</strong> (click to expand)</summary>

| Step | Screenshot |
|------|------------|
| Clean terminal | <img src="docs/screenshots/00-clean-terminal.png" width="300" alt="Clean terminal"> |
| Install opencode | <img src="docs/screenshots/01-install-complete.png" width="300" alt="Install opencode"> |
| Version check | <img src="docs/screenshots/02-version-check.png" width="300" alt="Version check"> |
| Installed files | <img src="docs/screenshots/03-installed-files.png" width="300" alt="Installed files"> |
| ELF interpreter | <img src="docs/screenshots/04-elf-interpreter.png" width="300" alt="ELF interpreter"> |
| opencode TUI | <img src="docs/screenshots/05-opencode-tui.png" width="300" alt="opencode TUI"> |
| Running opencode | <img src="docs/screenshots/06-opencode-working.png" width="300" alt="Running opencode"> |
| Newest version | <img src="docs/screenshots/07-opencode-newest-version.png" width="300" alt="Newest version"> |

</details>

## Credits

- [opencode](https://github.com/anomalyco/opencode) by [Anomaly](https://anoma.ly) — the AI coding CLI this project wraps
- [guysoft/opencode-termux](https://github.com/guysoft/opencode-termux) — the original Android port and Bionic compatibility shims that informed this work
- [Alpine Linux](https://alpinelinux.org/) — musl libc + libstdc++/libgcc_s packages

## License

MIT
