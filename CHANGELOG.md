# Changelog

The Android controller has a separate changelog in its own project.

## Apple TV 0.7.2

- Added **Cancel Pairing** to stop a manual search or pending approval
  without waiting for the timeout or disconnecting another controller.
- Update the Apple TV app and Bluetooth helper together. No Android update.

## Apple TV 0.7.1

- Added a **Bluetooth Controllers** submenu to the library and pause menu,
  with separate **Pair Controller 1** and **Pair Controller 2** actions.
- Manual searches and remote approvals target the chosen player slot.
  Either slot can be paired first, and pairing does not disconnect
  an already-connected controller.
- Upgrade the Apple TV app and Bluetooth helper together. No Android update.

## Apple TV 0.7.0

- Added two durable save-state slots per ROM, with a frame PNG, a timestamp,
  overwrite confirmation, and on-demand restore from the pause menu.
- Added Square Pixels (typically 8:7), 3:2, and 16:10 display modes. Preserved
  existing 4:3 and Widescreen preferences.

## Apple TV 0.6.0

- Menu and Player 1's TV Back open an in-game pause menu without closing the game.
- Added a persistent choice between original 4:3 and stretched widescreen.
- Added an in-game title picker with confirmation before switching,
  plus a controller connection option. Returning to the library leaves
  the current game paused and ready to resume.

## Apple TV 0.5.1

- Added explicit Player 1 and Player 2 advertising roles on Android so the
  second phone cannot take the first slot on retry.
- Added per-player recovery after a BLE disconnect or a stalled stream.
  Recovery of a previously approved handset does not reset the other port.
- Buffered local socket writes during temporary backpressure; added a
  regression test with a blocked reader and interleaved controller messages.
- Added bounded connection-event logging and documented the build,
  hardware tests, and public-release checklist.

## Apple TV 0.5.0

- Added two BLE controller slots and independent inputs on SNES ports 1
  and 2. Player 2 doesn't navigate the library.
- The emulator's port-isolation test passed on A1469. A later hands-on
  session reported cascading disconnects and swapped slots on retry;
  see the fixes above and current validation status in [testing](docs/testing.md).

## Apple TV 0.4.3

- Added a gameplay-scoped idle-sleep assertion and screen saver refresh.
  The user verified gameplay no longer went black during their test.

## Apple TV 0.4.2

- Split the library into `roms/` and `saves/`. Migration kept the original
  ROM and save bytes intact.

## Apple TV 0.4.1

- Moved BLE scanning out of the Apple TV UI process into a local helper
  after the in-app scan timed out. The handset-to-helper test and subsequent
  single-controller gameplay worked.

## Apple TV 0.4.0

- Introduced the Android BLE controller, on-TV approval, and a fallback
  to the original Apple remote.

## Apple TV 0.3.0

- Added a title picker for `.sfc` and `.smc` files and separate cartridge
  saves. Zelda and Mario both worked on the TV.

## Apple TV 0.2.0

- Added ROM playback in 4:3, PCM audio output, basic Apple-remote controls,
  and cartridge save RAM. Headless PCM was verified; audible sound was
  not confirmed.

## Apple TV 0.1.0

- First native home-screen appliance. Verified Snes9x 2005 initialization
  and Apple-remote input without using a ROM.
