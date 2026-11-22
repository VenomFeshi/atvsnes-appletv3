#!/bin/bash
set -euo pipefail

usage='Usage: bash scripts/install-ble-helper.sh user@host [--update]'
host="${1:?$usage}"
mode="${2:-install}"
if [[ $# -gt 2 || ( "$mode" != install && "$mode" != --update ) ]]; then
    echo "$usage" >&2
    exit 2
fi
cd "$(dirname "$0")/.."
test -x build/atvsnes-bluetooth
plutil -lint src/org.atvsnes.bluetooth.plist

IFS= read -r -d '' remote_script <<'REMOTE' || true
bin=/usr/local/libexec/atvsnes-bluetooth
plist=/Library/LaunchDaemons/org.atvsnes.bluetooth.plist
data=/var/mobile/Media/ATVSNES
[ ! -L "$data" ]
if [ ! -e "$data" ]; then
    install -d -o mobile -g mobile -m 750 "$data"
fi
test -d "$data"
if [ "$mode" = --update ]; then
    [ -f "$bin" ] && [ ! -L "$bin" ] && [ -f "$plist" ] && [ ! -L "$plist" ] ||
        { echo 'Expected an existing Bluetooth helper and launchd plist.' >&2; exit 1; }
elif [ -e "$bin" ] || [ -L "$bin" ] || [ -e "$plist" ] || [ -L "$plist" ]; then
    echo 'Bluetooth helper already installed; not overwriting.' >&2
    exit 1
fi
tmp=$(mktemp -d /var/tmp/atvsnes-helper.XXXXXX)
trap 'rm -f "$tmp/build/atvsnes-bluetooth" "$tmp/src/org.atvsnes.bluetooth.plist"; rmdir "$tmp/build" "$tmp/src" "$tmp" 2>/dev/null || true' EXIT
tar -xf - -C "$tmp"
ldid -S "$tmp/build/atvsnes-bluetooth"
if [ ! -d /usr/local/libexec ]; then
    install -d -o root -g wheel -m 755 /usr/local/libexec
fi
if [ "$mode" = --update ]; then
    cmp -s "$plist" "$tmp/src/org.atvsnes.bluetooth.plist" ||
        { echo 'Launchd plist differs; refusing to overwrite it.' >&2; exit 1; }
    backup=$(mktemp -d /usr/local/libexec/.atvsnes-previous.XXXXXX)
    install -o root -g wheel -m 755 "$tmp/build/atvsnes-bluetooth" "$backup/new"
    launchctl unload "$plist"
    if ! mv "$bin" "$backup/atvsnes-bluetooth" || ! mv "$backup/new" "$bin" ||
        ! launchctl load "$plist" || ! launchctl list org.atvsnes.bluetooth; then
        launchctl unload "$plist" 2>/dev/null || true
        if [ -f "$backup/atvsnes-bluetooth" ]; then
            mv "$backup/atvsnes-bluetooth" "$bin"
        fi
        launchctl load "$plist"
        exit 1
    fi
    echo "Previous helper: $backup/atvsnes-bluetooth"
else
    install -o root -g wheel -m 755 "$tmp/build/atvsnes-bluetooth" "$bin"
    install -o root -g wheel -m 644 "$tmp/src/org.atvsnes.bluetooth.plist" "$plist"
    launchctl load "$plist"
fi
launchctl list org.atvsnes.bluetooth
REMOTE

COPYFILE_DISABLE=1 tar --no-xattrs -cf - build/atvsnes-bluetooth src/org.atvsnes.bluetooth.plist |
    ssh -o BatchMode=yes -o ConnectTimeout=8 \
        -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -- "$host" \
        "set -e; mode='$mode'; $remote_script"
