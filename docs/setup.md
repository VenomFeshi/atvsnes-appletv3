# Setup and recovery

## Requirements

- A tested Apple TV 3 (`AppleTV3,2`, A1469) with Blackb0x, the `beigelist`
  appliance loader, SSH access, and `ldid` already working on the device.
  These scripts don't jailbreak a device or configure SSH keys.
- On a Mac: Clang, Python 3, the iPhoneOS 8.4 SDK, and an iOS 8 armv7
  compatible linker. Apple's [Xcode 6.4 download](https://developer.apple.com/services-account/download?path=/Developer_Tools/Xcode_6.4/Xcode_6.4.dmg)
  contains the SDK and `ld64-242`. The macOS command-line tools'
  `ld64-820.1` also worked with the 8.4 SDK in testing. Neither toolchain
  is included.
- The [Android BLE controller companion](https://github.com/feshi/atvsnes-android-controller)
  is only needed for Bluetooth play. It has its own APK build instructions.

## Configure SSH for this device

The scripts use SSH key authentication (`BatchMode=yes`). Generate a
dedicated key on the Mac if you don't already have one accepted by the
Apple TV. For a legacy SSH server that requires RSA:

```sh
ssh-keygen -t rsa -b 3072 -f ~/.ssh/atvsnes_device
```

Using your existing, trusted SSH access, add the **public** key
(`~/.ssh/atvsnes_device.pub`) to the root user's `~/.ssh/authorized_keys`
on the Apple TV. Never copy the private key to the device. Verify the
server fingerprint before accepting a new host key. Put the host alias
in your Mac's `~/.ssh/config`, not in the source tree:

```sshconfig
Host atvsnes-device
    HostName 192.0.2.10
    User root
    IdentityFile ~/.ssh/atvsnes_device
    IdentitiesOnly yes
```

Replace the example address with the Apple TV's LAN address. If the
private key has a passphrase, load it with `ssh-add ~/.ssh/atvsnes_device`
before running the scripts. Test with:

```sh
ssh -o BatchMode=yes -o HostKeyAlgorithms=+ssh-dss \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa atvsnes-device 'uname -m'
```

Only the individual device commands enable those legacy algorithms.
Don't expose the device's SSH service to the internet.

## Build and install

```sh
make host-test
make SDK=/path/to/iPhoneOS8.4.sdk LD64=/path/to/ld64-242

ATV=atvsnes-device  # or root@your-apple-tv-address
bash scripts/install-ble-helper.sh "$ATV"
bash scripts/deploy.sh "$ATV" --install
ssh -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    "$ATV" 'killall AppleTV'
```

The last command restarts the Apple TV interface, not the whole device. Exit
any running game first so cartridge RAM is written to disk. Legacy SSH
algorithms are enabled for these individual commands only; do not enable
them globally. Open **SNES** after the menu returns.

## Upgrade and migrate

For a version that changes both the app and helper, run:

```sh
bash scripts/install-ble-helper.sh "$ATV" --update
bash scripts/deploy.sh "$ATV" --update
```

For a first install, use `deploy.sh --install` (with the host argument
first) and omit `--update` from `install-ble-helper.sh`, as shown above.
Both scripts print the locations of previous builds on update. Upgrading
the helper disconnects active pads.
For upgrades from before v0.4.2, while no game is running:

```sh
bash scripts/migrate-library.sh "$ATV"
```

This moves existing ROM and save files into `roms/` and `saves/` without
overwriting anything. The original `game.sfc` still uses `saves/game.srm`.
Other saves use the complete ROM filename plus `.srm`. An optional
`titles.plist` in the parent `ATVSNES/` folder maps filenames to display names.

To test a new bundle without replacing the installed one, use
`bash scripts/deploy.sh "$ATV" --preflight`. `--verify-rom` also tests
uploaded ROMs for changing video and nonzero PCM. That heuristic can reject a
game that intentionally boots silently or shows a static screen for a while.

## Recovery

If the Apple TV interface fails to load, move only the ATVSNES bundle out of
the loader's directory and restart the interface. This doesn't touch games
or saves:

```sh
ssh -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    "$ATV" 'set -e
    d=$(mktemp -d /var/tmp/atvsnes-disabled.XXXXXX)
    mv /Applications/AppleTV.app/Appliances/ATVSNES.frappliance "$d/"
    killall AppleTV'
```

Use the exact backup paths printed by the updater to restore older builds.
Restore matching app and helper versions. If restoring a release before
v0.4.2, be aware that it expects the old, flat ROM/save layout.
