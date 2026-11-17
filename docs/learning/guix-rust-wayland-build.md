# Building a Rust Wayland Compositor (Smithay / PipeWire) in `guix shell --pure`

Learnings from compiling EWM (`libewm_core.so`, built on Smithay with PipeWire
screencast support) on Guix without polluting the declarative home profile with
Rust or a crates.io dependency tree.

---

## Working Pure Build Invocation

```sh
git clone https://codeberg.org/ezemtsov/ewm ~/src/ewm
cd ~/src/ewm/compositor
guix shell --pure rust rust:cargo pkg-config nss-certs bash-minimal \
     clang-toolchain libinput libseat eudev libxkbcommon mesa wayland \
     glib libdisplay-info pipewire \
     -- bash -c 'LIBCLANG_PATH=$GUIX_ENVIRONMENT/lib cargo build --features=screencast'
```

Verified clean (empty `target/`) against EWM `dc5eb71` in 1m23s, producing
`target/debug/libewm_core.so` (see `docs/stages/stage-03-REPORT.md`).

---

## Key Package & Environment Learnings

### 1. Why `--pure` Is Worth Its Scaffolding
`--pure` makes missing dependencies fail loudly at build time instead of
silently binding against libraries from the ambient user profile that may not
exist at runtime. The price of `--pure` is two explicit additions (`nss-certs`
and `LIBCLANG_PATH`).

### 2. `bindgen` (`libspa-sys`) Needs `clang-toolchain` + `LIBCLANG_PATH`
* `--features=screencast` pulls in `libspa-sys` (PipeWire SPA bindings), which
  runs `bindgen` at build time.
* `bindgen` via `clang-sys` requires `libclang.so`. Guix does not place
  `libclang.so` on a default path searched by `clang-sys`.
* **Fix:** Include `clang-toolchain` and `bash-minimal` in `guix shell --pure`,
  and pass `LIBCLANG_PATH=$GUIX_ENVIRONMENT/lib` inside `bash -c '...'` so
  `$GUIX_ENVIRONMENT` expands inside the subshell.

### 3. Cargo Crates.io Fetch Fails in `--pure` Without `nss-certs`
* `guix shell --pure` clears `SSL_CERT_FILE`, causing Cargo to fail TLS
  verification against `index.crates.io` before compiling anything.
* **Fix:** Add `nss-certs` to the `guix shell --pure` manifest.

### 4. Required C `pkg-config` Libraries vs Pure-Rust Crates
* **Required C libraries:**
  * `glib` — `glib-sys` queries `glib-2.0.pc` for GIO (XDG desktop app
    enumeration).
  * `libdisplay-info` — `libdisplay-info-sys` queries it for EDID monitor
    parsing.
  * `pipewire` — `libspa-sys` requires `libpipewire-0.3.pc` when building with
    `--features=screencast`.
  * `libinput`, `libseat`, `eudev`, `libxkbcommon`, `mesa`, `wayland` — core
    Smithay DRM/KMS/input/EGL stack.
* **Not needed (confirmed by clean rebuild after removal):**
  * `wayland-protocols` — the Rust `wayland-protocols` crate vendors its XML
    protocol definitions.
  * `dbus` — `zbus` is a pure-Rust D-Bus implementation.
  * `pixman` — Smithay's GL renderer does not link against `pixman`.
