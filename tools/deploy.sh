#!/usr/bin/env bash
# Deploy a mod folder from this repo into an r2modman profile.
#
#   tools/deploy.sh <source-mod-dir> <profile-name> [dest-mod-name]
#
# dest-mod-name defaults to the source directory's basename. Pass it explicitly
# when the source dir is not named after the mod -- the package source lives at
# package/mod/, which would otherwise install as a folder called "mod".
#
# The copy is gated on the SYNTAX CHECKER'S OWN EXIT CODE. It is deliberately
# not `check | grep ... && cp`, which tests grep's exit code and has shipped a
# broken file twice. After copying it md5sums both paths and refuses to claim
# success unless they match.
set -u

SRC="${1:?usage: deploy.sh <source-mod-dir> <profile-name>}"
PROFILE="${2:?usage: deploy.sh <source-mod-dir> <profile-name>}"

PY="/c/Users/Daan/AppData/Local/Programs/Python/Python313/python.exe"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODNAME="${3:-$(basename "$SRC")}"
DEST="/c/Users/Daan/AppData/Roaming/Thunderstore Mod Manager/DataFolder/GrainRot/profiles/$PROFILE/shimloader/mod/$MODNAME"

SRC_LUA="$SRC/Scripts/main.lua"
DEST_LUA="$DEST/Scripts/main.lua"

if [ ! -f "$SRC_LUA" ]; then
    echo "REFUSED: no such file: $SRC_LUA" >&2
    exit 1
fi
if [ ! -d "$(dirname "$(dirname "$DEST")")" ]; then
    echo "REFUSED: profile '$PROFILE' has no shimloader/mod directory" >&2
    exit 1
fi

echo "== syntax gate =="
if "$PY" "$REPO/tools/luasyntax.py" "$SRC_LUA"; then
    mkdir -p "$DEST/Scripts"
    cp "$SRC_LUA" "$DEST_LUA"
    # UE4SS enables a mod folder by the presence of an empty enabled.txt.
    : > "$DEST/enabled.txt"
    echo "copied -> $DEST_LUA"
else
    echo "REFUSED: syntax check failed, nothing was copied" >&2
    exit 1
fi

echo
echo "== md5 both paths =="
SRC_MD5="$(md5sum "$SRC_LUA" | cut -d' ' -f1)"
DEST_MD5="$(md5sum "$DEST_LUA" | cut -d' ' -f1)"
printf '%s  source  %s\n' "$SRC_MD5" "$SRC_LUA"
printf '%s  profile %s\n' "$DEST_MD5" "$DEST_LUA"

if [ "$SRC_MD5" = "$DEST_MD5" ]; then
    echo "MATCH: the deployed file is the file in the repo."
else
    echo "MISMATCH: the deployed file is NOT what is in the repo." >&2
    exit 1
fi

echo
echo "== what is now in the profile =="
find "$DEST" -type f -printf '%-70p %s bytes\n' 2>/dev/null || find "$DEST" -type f
