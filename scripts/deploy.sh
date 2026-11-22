#!/bin/bash
set -euo pipefail

usage='Usage: bash scripts/deploy.sh user@host [--preflight|--install|--update] [--verify-rom]'
host="${1:?$usage}"
mode="${2:---preflight}"
verify="${3:-}"
if [[ $# -gt 3 || ( "$mode" != --preflight && "$mode" != --install && "$mode" != --update ) ||
      ( -n "$verify" && "$verify" != --verify-rom ) ]]; then
    echo "$usage" >&2
    exit 2
fi
cd "$(dirname "$0")/../build"
test -x atv-core-smoke
test -x ATVSNES.frappliance/ATVSNES

IFS= read -r -d '' remote_script <<'REMOTE' || true
tmp=$(mktemp -d /var/tmp/atvsnes.XXXXXX)
bundle=ATVSNES.frappliance
parent=/Applications/AppleTV.app/Appliances
dest="$parent/$bundle"
stage=
lock=
backup=
restore=
cleanup() {
    if [ -n "$restore" ] && [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$restore/$bundle" "$dest" && rmdir "$restore" ||
            echo "Restore previous bundle from $restore" >&2
    fi
    rm -f "$tmp/$bundle/"* "$tmp/atv-core-smoke"
    rmdir "$tmp/$bundle" "$tmp" 2>/dev/null || true
    if [ -n "$stage" ]; then
        rm -f "$stage/"*
        rmdir "$stage" 2>/dev/null || true
    fi
    if [ -n "$lock" ]; then
        rmdir "$lock" 2>/dev/null || true
    fi
}
trap cleanup EXIT
tar -xf - -C "$tmp"
ldid -S "$tmp/atv-core-smoke"
ldid -S "$tmp/$bundle/ATVSNES"
"$tmp/atv-core-smoke" "$tmp/$bundle/ATVSNES"
if [ "$verify" = --verify-rom ]; then
    set --
    dir=/var/mobile/Media/ATVSNES
    if [ -d "$dir/roms" ]; then dir="$dir/roms"; fi
    for rom in "$dir"/*.[Ss][Ff][Cc] "$dir"/*.[Ss][Mm][Cc]; do
        if [ -f "$rom" ] && [ ! -L "$rom" ]; then
            set -- "$@" "$rom"
        fi
    done
    [ "$#" -gt 0 ] || { echo "No uploaded ROMs found" >&2; exit 1; }
    "$tmp/atv-core-smoke" --rom "$@"
fi
[ "$mode" != --preflight ] || exit 0

# Keep a complete backup on updates; don't restart a possibly in-use UI.
mkdir "$parent/.atvsnes-install.lock"
lock="$parent/.atvsnes-install.lock"
if [ "$mode" = --update ]; then
    if [ ! -d "$dest" ] || [ -L "$dest" ] ||
        ! grep -Fq '<string>org.atvsnes.frontrow.appliance</string>' "$dest/Info.plist"; then
        echo "Expected an existing ATVSNES bundle at $dest" >&2
        exit 1
    fi
else
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "Refusing to overwrite $dest" >&2
        exit 1
    fi
fi
stage=$(mktemp -d "$parent/.atvsnes.XXXXXX")
cp -p "$tmp/$bundle/"* "$stage/"
chown -R root:wheel "$stage"
chmod 755 "$stage"
if [ "$mode" = --update ]; then
    backup=$(mktemp -d /Applications/.atvsnes-previous.XXXXXX)
    restore="$backup"
    mv "$dest" "$backup/$bundle"
fi
mv "$stage" "$dest"
stage=
restore=
cache=/var/mobile/Library/Caches/AppleTV/MainMenu
icon="$cache/org.atvsnes.frontrow.appliance@1080.png"
if [ -d "$cache" ] && [ ! -e "$icon" ] && [ ! -L "$icon" ]; then
    install -o mobile -g mobile -m 644 "$dest/TopRowIcon.png" "$icon" ||
        echo "Could not populate the optional menu icon cache." >&2
fi
echo "Installed $dest. Restart the Apple TV UI when ready."
if [ -n "$backup" ]; then
    echo "Previous bundle: $backup/$bundle"
fi
REMOTE

# No appliance is made visible until the exact signed files pass dyld on-device.
COPYFILE_DISABLE=1 tar --no-xattrs -cf - ATVSNES.frappliance atv-core-smoke |
    ssh -o BatchMode=yes -o ConnectTimeout=8 \
        -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -- "$host" \
        "set -e; mode='$mode'; verify='$verify'; $remote_script"
