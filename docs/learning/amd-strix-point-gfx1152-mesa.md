# AMD Strix Point (`gfx1152` / Radeon 890M) Crash on Guix Mesa with LLVM 18

Learnings from launching a Wayland DRM/KMS compositor on the Framework Laptop 13
(AMD Ryzen AI 9 HX 370 / Radeon 890M, `gfx1152`) running Guix System.

---

## Symptom

Starting a GL/EGL Wayland compositor on physical display `eDP-1`
(`2880x1920@120Hz`) aborts immediately at runtime in the Mesa shader compiler:

```text
LLVM ERROR: Cannot select...
```

## Root Cause

The Framework 13 Strix Point integrated GPU is `gfx1152` (Radeon 890M). When
Guix System packages Mesa against LLVM 18 (`llvm-for-mesa-18.1.8`), LLVM lacks
the `gfx1152` AMDGPU shader compiler target definitions and aborts during
pipeline compilation.

## Workaround

Force KMS software rasterization via environment variables when launching the
compositor (encapsulated in `make ewm-launch`):

```sh
LIBGL_ALWAYS_SOFTWARE=1 \
MESA_LOADER_DRIVER_OVERRIDE=kms_swrast \
HSA_OVERRIDE_GFX_VERSION=11.0.0
```

This bypasses LLVM 18 hardware shader compilation and drives the `2880x1920@120Hz`
panel via DRM KMS software rasterization until Guix upgrades Mesa's LLVM input
to LLVM 19+.
