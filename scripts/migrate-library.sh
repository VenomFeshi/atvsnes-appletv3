#!/bin/bash
set -euo pipefail

host="${1:?Usage: bash scripts/migrate-library.sh user@host}"
IFS= read -r -d '' remote_script <<'REMOTE' || true
root=/var/mobile/Media/ATVSNES
[ -d "$root" ] && [ ! -L "$root" ]

move_library() {
    action=$1
    for file in "$root"/*.[Ss][Ff][Cc] "$root"/*.[Ss][Mm][Cc] "$root"/*.[Ss][Rr][Mm]; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        case "$file" in
            *.[Ss][Rr][Mm]) folder=saves ;;
            *) folder=roms ;;
        esac
        name=${file##*/}
        dest="$root/$folder/$name"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            echo "Refusing to overwrite $dest" >&2
            exit 1
        fi
        if [ "$action" = move ]; then
            mv -n "$file" "$dest"
            if [ -e "$file" ]; then
                echo "Could not move $file to $dest" >&2
                exit 1
            fi
            echo "$folder/$name"
        fi
    done
}

move_library check
for folder in "$root/roms" "$root/saves"; do
    if [ ! -e "$folder" ] && [ ! -L "$folder" ]; then
        install -d -o mobile -g mobile -m 750 "$folder"
    fi
    [ -d "$folder" ] && [ ! -L "$folder" ]
done
move_library move
REMOTE

ssh -o BatchMode=yes -o ConnectTimeout=8 \
    -o HostKeyAlgorithms=+ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -- "$host" \
    "set -e; $remote_script"
