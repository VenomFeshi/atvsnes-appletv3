# Test registry and troubleshooting

## Verified so far

| Check | Result |
| --- | --- |
| Native UI, ROM library, play and Apple remote | Verified on A1469; Zelda and Mario played on HDMI. |
| Emulated video and PCM | Both supplied test games produced changing frames and nonzero stereo PCM. This doesn't confirm audible HDMI output. |
| Single-phone BLE | Galaxy A71 (Android 10): USB-driven button press and release reached the Apple TV over BLE, and later gameplay worked. |
| Player 2 setup and D-pad on Android 0.2.1 | Infinix X669 (Android 12): all four arrows rendered correctly after upgrading from 0.1.0. The Apple TV detected the Player 2 advertisement; gameplay was not part of this check. |
| Android 0.3.0 thumbstick and button layout | APK installed via ADB on Galaxy A71; verified layout on the phone. The APK build runs Java checks for joystick dead zone, directions, diagonals, and adjacent-button hit areas. Physical play feel remains to be checked. |
| Gameplay idle protection | A1469 accepted the playback assertion. The user confirmed the display stayed on during gameplay. |
| v0.6.0 pause and display | A1469 playback diagnostic verified overlay selection, centered 4:3, full-width stretch, preserved live RAM and paused frame, resuming, and saving on close. Remote navigation and appearance on HDMI still need a hands-on check. |
| v0.7.0 save states and display modes | The Mac tests cover two independent slots, per-ROM isolation, overwrite, corrupt data rejection, and the five display geometries. The A1469 diagnostic saved both slots with frame PNGs for Zelda and Mario, then restored and advanced each in a fresh process. Save menu navigation and preview appearance on HDMI still need a hands-on check. |
| v0.7.1 targeted pairing | Scripted radio tests checked role filtering, either slot first, and no disconnect when choosing an already paired slot. The A1469 helper started a Player 2 search without starting one for Player 1. The TV menu still needs a hands-on check with phones. |
| v0.7.2 cancel pairing | Scripted radio tests cover cancel during discovery and during approval, ignoring late input, keeping the other slot active, and manually starting again. The A1469 helper acknowledged cancellation without waiting for the timeout. |
| Two SNES controller ports | Mario ROM tested on A1469: independent port masks and releases, with no input on unused ports. |
| v0.5.1 controller recovery | Automated tests passed on macOS and A1469. They cover role selection, approval, rejecting a different phone during recovery, and Player 2 recovery without clearing Player 1. The socket test delivered 1,600 interleaved messages with a blocked reader. |
| Simultaneous real handsets on v0.5.1 | Still needs a hands-on regression test. Earlier dual-phone sessions on v0.5.0 could drop both controllers or attach the wrong phone on retry. |

## Repeatable checks

```sh
make host-test
./build/host-core-smoke --rom "/path/to/your/game.sfc"
```

The first command does not require ROMs. It tests catalog filtering and
save paths, BLE packet parsing, socket backpressure, and scripted BLE
connection events. The ROM check loads a supplied game, runs 600 frames,
and checks the two port masks directly through the core.

For device checks, see these Makefile targets:

- `build/atv-idle-test`: on-device power assertion plus mocked BackRow timer.
- `build/atv-pause-test ROM TEMP_SAVE`: checks the frame and live save RAM
  survive pause, video hiding and resume, without writing the save until
  exit. Use a separate temporary path, never a real cartridge save.
- `build/atv-state-test --write ROM TEMP_DIRECTORY` followed by the same
  command with `--read`: verifies both snapshots and fresh-process restore.
  Use a new temporary directory writable by `mobile` and a ROM with SRAM.
- `build/atv-bluetooth-probe`: confirms the Apple TV can scan for BLE. Add
  `--player2` to look only for a Player 2 advertisement without connecting.
- `build/atv-controller-link-test`: `--scan` validates helper startup and
  cancellation; `--scan2` requests Player 2 first; `--helper` tests one active phone; `--two` expects both
  phones to send B, Right, and release in order. Run as `mobile`, when
  SNES doesn't already have an active controller session. Approval in this
  standalone diagnostic is automatic; the real app requires the remote.

## Two-handset regression test

1. Update both handset APKs. Set one to Player 1 and one to Player 2.
2. Connect both as described in the [README](../README.md), then use a game
   with simultaneous local multiplayer. Press and hold controls on both
   phones for several minutes. *Super Mario World* is useful for checking
   separate ports across turns, not simultaneous input.
3. On Player 2, tap **Stop Bluetooth**, verify Player 1 stays responsive,
   then tap **Start Bluetooth** again without leaving the game. Leave both
   touch pads neutral until the second phone reconnects. Repeat for Player 1.
4. If a reconnect times out, confirm the phone's player role, then open
   **Bluetooth Controllers** from the pause menu or library and approve
   the matching slot again with the Apple remote.

If it fails, note the two player roles, game/mode, time since starting,
which phone stopped responding first, and any on-screen status. Keep the
phone apps visible; switching apps or locking the phone can end a session.

The helper records connection transitions (not device addresses or button
presses) in `/var/mobile/Media/ATVSNES/.controller-events.log`. The log is
local and bounded to roughly 32 KiB. To inspect recent events:

```sh
ssh -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    root@192.0.2.10 'tail -n 30 /var/mobile/Media/ATVSNES/.controller-events.log'
adb -s PHONE_SERIAL logcat -d -s 'ATVSNESController:I'
```

Replace the example address/serial, and review output before sharing it.
