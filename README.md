# ATVSNES — SNES for Apple TV 3

A native SNES emulator frontend for an already-jailbroken **Apple TV 3**
with the `beigelist` appliance loader. It runs Snes9x 2005 locally, keeps
ROMs and saves separate, and supports two Android phones as Bluetooth LE
controllers. It does not include any rom games.

**Tested target:** `AppleTV3,2` (A1469, armv7) with Blackb0x. Other Apple TV 
models and software versions aren't verified. This project uses a Samsung Galaxy A51 
and Galaxy A71 as BLE controllers. The Android app requires Android 6+ and a phone
that can advertise as a BLE peripheral.

## Set up

1. [Build and install the Apple TV app and Bluetooth helper](docs/setup.md).
2. Install the [Android controller companion project](https://github.com/VenomFeshi/atvsnes-android-controller)
   on each phone. Use its build instructions or
   [download the APK from GitHub Releases](https://github.com/VenomFeshi/atvsnes-android-controller/releases/latest/download/ATVSNES-Controller.apk)
   once the release is published.
3. To add your own uncompressed `.sfc` or `.smc` files, substitute
   your Apple TV's SSH address:

   ```sh
   bash scripts/upload-rom.sh root@192.0.2.10 "/path/to/your/game.sfc"
   ```

   Reopen **SNES** to refresh the library. No interface restart is needed
   just to add games.

## Play with one or two phones

**Use Apple TV v0.5.1 and Android controller v0.2.0 or newer together for
two-player setup.** If the phone app has no **Player 1 / Player 2** button,
it's an older build that always advertises as Player 1. For the current
thumbstick layout, use Android v0.3.0 or newer.

1. Open **ATVSNES Controller** on the first phone, leave it on **Player 1**,
   and tap **Start Bluetooth**. Allow **Nearby devices** if prompted.
2. Open **SNES → Bluetooth Controllers → Pair Controller 1** on the
   Apple TV. In the library, **Play/Pause** is a shortcut to the controller
   menu. When **Player 1 found** appears, approve it with **Select** on the
   Apple remote.
3. On the second phone, tap the role button until it shows **Player 2**,
   then tap **Start Bluetooth**. Choose **Pair Controller 2** and approve
   **Player 2** with **Select** on the Apple remote.
4. When the TV says **Players 1 and 2 connected**, launch a game and select
   its own two-player mode. *Super Mario World* alternates turns; use a game
   with simultaneous multiplayer to test both pads at once.

Keep the phone apps visible. No Wi-Fi, mobile data, or pairing in the Apple
TV's system settings is needed. On Android v0.3.2, drag the left thumbstick
to move (including diagonals). A/B/X/Y use the original spacing and
separate touch areas. Use two touches for combos like **Y+B** in
*Super Mario World*. **Start Bluetooth** is above
**TV Back**. Player 1 can navigate the SNES library and
use **TV Back** to open the pause menu. Player 2 controls the game only. Neither
phone controls the main Apple TV interface. You can pair either slot first;
manual pairing for one slot does not disconnect the other.
Choose **Cancel Pairing** in the controller menu to stop a search or dismiss
a pending approval without waiting for the timeout. It leaves connected
controllers alone and won't start another search until you choose a slot.

If a pad drops, leave its app visible and give it up to 25 seconds to
reconnect. Release held buttons before resuming. If it doesn't reconnect,
open **Bluetooth Controllers** from the pause menu or the library and
choose the matching slot. Then approve it with the Apple remote. See
[troubleshooting and test status](docs/testing.md) for diagnostics.

### Apple remote and game files

| Apple remote | In game |
| --- | --- |
| Arrows | SNES D-pad for Player 1 |
| Select (center) | SNES A for Player 1 |
| Play/Pause | SNES Start for Player 1 |
| Menu | Pause the game and open the in-game menu |

### In-game menu

Press **Menu** on the Apple remote or **TV Back** on Player 1's phone.
Use **Up/Down** and **Select/A** to choose an option:

- **Resume Game** continues from the same spot.
- **Save States** has two slots per game, each with a screenshot preview.
  Pick a slot and choose **Save State**. To continue later, launch the
  same game, open **Save States**, select the slot, and choose **Load State**.
  Overwriting asks for confirmation; loading replaces your current progress.
- **Display** offers **Original 4:3**, **Widescreen 16:9 (stretch)**,
  **Square Pixels (usually 8:7)**, **3:2**, and **16:10**. None crop the
  picture. The last choice is remembered for future games.
- **Change Game** opens the title list without closing the current game.
  Switching to a different title requires confirmation.
- **Bluetooth Controllers** lets you pair or reconnect either controller
  slot without closing the game.
- **Return to Library** keeps the game paused. Select the title marked
  **Paused** to resume it. Leaving SNES entirely closes the game.

Games live in `/var/mobile/Media/ATVSNES/roms/`. The emulator creates `.srm`
cartridge saves in `/var/mobile/Media/ATVSNES/saves/`; you don't need a
`.srm` to add a game. Save states are stored separately under
`/var/mobile/Media/ATVSNES/saves/states/` and survive a restart. They are tied
to the exact ROM and compatible emulator build; keep normal in-game saves for
long-term backups. Pausing alone keeps progress only in memory. Normal screen
saver and sleep behavior resumes while paused.

## Project notes

- [Setup, upgrades, and recovery](docs/setup.md)
- [Architecture and Bluetooth protocol](docs/architecture.md)
- [Test registry and troubleshooting](docs/testing.md)
- [Changelog](CHANGELOG.md)
- [Third-party notices and publication checklist](docs/publication.md)

## Credits

- [Snes9x 2005](https://github.com/libretro/snes9x2005) and the
  [libretro project](https://www.libretro.com/) provide the emulator
  core and its frontend interface.
- [Blackb0x](https://github.com/NSSpiral/Blackb0x) is the existing jailbreak
  used on the test Apple TV. The `beigelist` appliance loader is required.
- [PlexATV3](https://github.com/huguesdelamure/PlexATV3) provided a reference
  for native BackRow appliance integration and power management.
- [Kodi](https://kodi.tv/) on the device provided an example of a
  legacy Apple TV appliance bundle.
