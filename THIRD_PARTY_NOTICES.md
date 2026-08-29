# Third-party notices

## Goldberg Steam Emulator

- Source: <https://gitlab.com/Mr_Goldberg/goldberg_emulator>
- Pinned commit: `475342f0d8b2bd7eb0d93bd7cfdd61e3ae7cda24`
- License: GNU Lesser General Public License, version 3 or later

Goldberg is fetched and built as a separate third-party shared library. Its original license and experimental-build readme are copied into packaged output under `LICENSES/`.

The pinned Goldberg experimental build also compiles its vendored Microsoft Detours, Dear ImGui, Gamepad Input Library and System sources. The applicable MIT notices for the first three are included under `licenses/`; System uses LGPL-3.0-or-later, covered alongside Goldberg's LGPL text. License notices embedded in vendored source headers remain available in the pinned source checkout.

## Protocol Buffers

- Source: <https://github.com/protocolbuffers/protobuf>
- Version selected by the pinned vcpkg tree: `3.21.12`
- License: BSD-3-Clause

Protocol Buffers is statically linked into the Goldberg DLL. Its copyright file installed by vcpkg is copied into the runtime package.

## vcpkg

- Source: <https://github.com/microsoft/vcpkg>
- Pinned commit: `4746870785b3b4a77556cfc9cf260b4034724e10`
- License: MIT

vcpkg is a build-time dependency and is not copied into the runtime package.
