# Publication checklist and third-party notices

The repository owner should choose (and have the rights to grant) a
license for the original frontend before publishing or accepting
contributions. These notes aren't a project license.

## Third-party software

- **Snes9x 2005**: fetched at the exact commit in the `Makefile`.
  Read its [upstream copyright and terms](https://github.com/libretro/snes9x2005/blob/a79dfe9047e7fec58808aefe48ad2bf499c7af11/copyright)
  before redistributing anything linked with it, including the appliance
  binary. That file contains multiple notices including Snes9x's
  noncommercial terms. The build includes a copy inside the bundle.
- **PlexATV3**: the [MIT-licensed project](https://github.com/huguesdelamure/PlexATV3)
  served as a reference for the BackRow appliance and idle behavior.
  Its MIT notice is reproduced below.
- **Blackb0x and Kodi**: [Blackb0x](https://github.com/NSSpiral/Blackb0x)
  provides the tested device setup; the installed [Kodi](https://kodi.tv/)
  bundle was a reference for the appliance layout. Neither is bundled.
- **Apple/Google tooling**: users obtain their own SDKs and build tools.
  Don't upload SDK copies, firmware, licensed graphics, or project signing
  keys. Blackb0x and the appliance loader are external prerequisites.

### PlexATV3 notice

MIT License

Copyright (c) 2026 PlexATV3 contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Before publishing

1. Review the planned Git contents and history. Keep ROMs, cartridge saves,
   local photos, build output, private IPs, device serials, SSH credentials,
   and signing keys out of the public tree.
2. Run `make host-test` and build the appliance from a clean checkout.
3. Complete the [two-handset hardware test](testing.md) and update the
   verification table with what actually worked. Record remaining limitations
   and the paired Apple TV/Android release versions in `CHANGELOG.md`.
4. Review the third-party terms and select the project license. Verify
   redistribution rights separately before publishing signed APKs or an
   appliance binary. A source-only release is easier to audit.

## Current scope and backlog

Display modes include original 4:3, stretched 16:9, square pixels, 3:2,
and 16:10. Returning to the library keeps one game paused in memory.
Use one of the two per-ROM save-state slots to keep an exact resume point
across sessions. The Android controller works inside SNES, not as a remote
for the main Apple TV interface.
