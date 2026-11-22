# Architecture

- **Apple TV frontend**: an armv7 `.frappliance`, loaded by `beigelist`.
  `src/appliance.m` connects to the legacy BackRow UI. `src/catalog.m`
  discovers ROMs and chooses separate cartridge save paths.
- **Playback**: `src/game.c` hosts the pinned Snes9x 2005 libretro core.
  `src/playback.m` runs frames on `CADisplayLink`, presents RGB565 video
  through Core Animation, and forwards stereo PCM to Audio Queue.
  `src/idle.m` holds a gameplay-scoped power assertion and refreshes
  BackRow's separate screen saver timer.
- **Pause menu**: `src/pause_menu.m` renders an overlay above the last video
  frame. `src/appliance.m` routes input to the overlay or library while
  paused. Playback stops its display clock, audio, and idle guard, but
  does not unload the core or save RAM until the game actually closes.
- **Save states**: `src/state_store.m` writes two atomic binary plist files
  per ROM under `saves/states/<ROM SHA-256>/`. Each file contains the pinned
  core's serialized state, its checksum, a timestamp, and a PNG of the
  last displayed game frame (without the UI overlay). The format checks the
  ROM, core revision, build architecture, size, and state checksum before
  loading. These are local saves, not a portable import format.
- **Controller**: the Android app advertises as a legacy BLE GATT
  peripheral. It neither opens a network socket nor asks for internet
  permission. The Apple TV helper is a CoreBluetooth central running as
  `mobile`. Scanning directly from the old TV UI process timed out on the
  test device even though the same scanner worked from a standalone process.
- **Local bridge**: the frontend and helper communicate over a private,
  same-UID Unix socket at `ATVSNES/.controller.sock`. The helper scans only
  when requested or recovering an approved pad. Closing the frontend
  connection ends that session. A second local client cannot displace
  the active frontend.

## Bluetooth roles and packets

| Role | GATT service UUID |
| --- | --- |
| Player 1 / legacy controller | `854DEE83-73CA-4763-B413-75D42FA032F0` |
| Player 2 | `854DEE83-73CA-4763-B413-75D42FA032F2` |

Both services use the notify characteristic
`854DEE83-73CA-4763-B413-75D42FA032F1`. Its three bytes are `1` (protocol
version), then the low and high bytes of a little-endian mask. Bits 0–11
are the libretro SNES buttons. Bit 12 is the app-specific **TV Back** action
and is only acted on for Player 1. The phone sends state changes immediately
and sends a full snapshot on a 100 ms heartbeat while idle.

The local protocol uses newline-delimited UTF-8. The frontend sends
`PAIR <zero-based port>` to start a targeted search and
`APPROVE <zero-based port>` to approve that pending slot. `CANCEL` clears
only the pending manual search or approval; `C <status>` confirms the
request and lets the frontend discard any queued approval prompt. The helper still
understands the older `START2`, `ADD`, and bare `APPROVE` commands for
rollback. It sends `S <status>`, `P <zero-based port>
<approval prompt>`, `B <zero-based port> <decimal mask>`, or `E <error>`.
The writer preserves pending messages through partial writes or temporary
backpressure. Queued data is bounded so a stalled UI cannot grow memory
indefinitely.

The physical Apple remote approves an initial connection for each role.
Approval is scoped to the session; it isn't encrypted Bluetooth bonding.
After a link drops, only that port is cleared. For up to 25 seconds the
helper looks for the same CoreBluetooth identifier advertising the same
role. A different identifier requires approval again in the library.
After reconnection the first neutral packet re-enables input.
