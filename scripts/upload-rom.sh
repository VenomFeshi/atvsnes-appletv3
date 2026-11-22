#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 || ! -f "$2" ]]; then
    echo "Usage: bash scripts/upload-rom.sh user@host path-to-your-rom.sfc-or-smc" >&2
    exit 2
fi
name=${2##*/}
case "$name" in
    .*|*$'\n'*|*$'\r'*)
        echo "Use a visible filename without line breaks." >&2
        exit 2 ;;
    *.[Ss][Ff][Cc]|*.[Ss][Mm][Cc]) ;;
    *)
        echo "Upload an uncompressed .sfc or .smc file." >&2
        exit 2 ;;
esac
hash=$(shasum -a 256 < "$2")
hash=${hash%% *}
IFS= read -r -d '' remote_script <<'REMOTE' || true
IFS= read -r name
case "$name" in
    ""|.*|*/*) exit 2 ;;
    *.[Ss][Ff][Cc]|*.[Ss][Mm][Cc]) ;;
    *) exit 2 ;;
esac
root=/var/mobile/Media/ATVSNES
dir="$root/roms"
dest="$dir/$name"
for folder in "$root" "$dir" "$root/saves"; do
    if [ ! -e "$folder" ] && [ ! -L "$folder" ]; then
        install -d -o mobile -g mobile -m 750 "$folder"
    fi
    if [ ! -d "$folder" ] || [ -L "$folder" ]; then
        echo "Not a regular directory: $folder" >&2
        exit 1
    fi
done
if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "Refusing to overwrite $dest or follow a symlink" >&2
    exit 1
fi
tmp=$(mktemp "$dir/.upload.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
hash=$(sha256sum "$tmp")
[ "${hash%% *}" = "$expected" ] || { echo "ROM upload checksum mismatch" >&2; exit 1; }
chown mobile:mobile "$tmp"
chmod 640 "$tmp"
ln "$tmp" "$dest"
echo "ROM uploaded and verified at $dest"
REMOTE
{ printf '%s\n' "$name"; cat < "$2"; } | ssh -o BatchMode=yes -o ConnectTimeout=8 \
    -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -- "$1" \
    "set -e; expected='$hash'; $remote_script"
