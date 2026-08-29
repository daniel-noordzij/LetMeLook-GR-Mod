#!/usr/bin/env bash
# Build the Thunderstore upload zip from package/.
#
#   tools/package.sh
#
# Produces dist/LetMeLook-<version>.zip, with the version read out of
# package/manifest.json so it can never drift from what Thunderstore sees.
#
# Zip layout, matching a known-good Grain Rot shimloader Lua package:
#   manifest.json  README.md  CHANGELOG.md  icon.png
#   mod/enabled.txt
#   mod/Scripts/main.lua
set -u

PY="/c/Users/Daan/AppData/Local/Programs/Python/Python313/python.exe"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/package"

# Gate on the syntax checker's own exit code, exactly as deploy does. Shipping a
# zip that does not parse is worse than shipping nothing.
echo "== syntax gate =="
if ! "$PY" "$REPO/tools/luasyntax.py" "$SRC/mod/Scripts/main.lua"; then
    echo "REFUSED: syntax check failed, no zip was built" >&2
    exit 1
fi

NAME="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$SRC/manifest.json" name)"
VERSION="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$SRC/manifest.json" version_number)"
OUT="$REPO/dist/$NAME-$VERSION.zip"

echo
echo "== required files =="
missing=0
for f in manifest.json README.md CHANGELOG.md icon.png mod/Scripts/main.lua mod/enabled.txt; do
    if [ -e "$SRC/$f" ]; then
        printf '  present  %s\n' "$f"
    else
        printf '  MISSING  %s\n' "$f"; missing=1
    fi
done
[ "$missing" -eq 0 ] || { echo "REFUSED: package is incomplete" >&2; exit 1; }

# The icon is hand-authored, so it is checked rather than trusted: Thunderstore
# rejects anything that is not a 256x256 PNG, and it rejects it after the upload.
echo
echo "== icon =="
"$PY" -c '
import struct, sys
data = open(sys.argv[1], "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit("  REFUSED: package/icon.png is not a PNG")
width, height = struct.unpack(">II", data[16:24])
print(f"  {width}x{height}, {len(data)} bytes")
if (width, height) != (256, 256):
    sys.exit(f"  REFUSED: Thunderstore requires exactly 256x256, got {width}x{height}")
print("  256x256 PNG: OK")
' "$SRC/icon.png" || exit 1

# Nothing but the mod may ship: no probes, no dev scripts.
EXTRA="$(find "$SRC/mod/Scripts" -type f ! -name 'main.lua' 2>/dev/null)"
if [ -n "$EXTRA" ]; then
    echo "REFUSED: Scripts/ must contain only main.lua, but also has:" >&2
    echo "$EXTRA" >&2
    exit 1
fi

mkdir -p "$REPO/dist"
rm -f "$OUT"

# Build the zip with Python so this needs no external zip binary, and so the
# archive is written with forward-slash paths regardless of platform.
"$PY" - "$SRC" "$OUT" <<'PYEOF'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
members = ["manifest.json", "README.md", "CHANGELOG.md", "icon.png",
           "mod/enabled.txt", "mod/Scripts/main.lua"]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in members:
        z.write(os.path.join(src, name.replace("/", os.sep)), name)
print("wrote", out)
PYEOF

echo
echo "== zip contents =="
"$PY" -c '
import zipfile,sys
with zipfile.ZipFile(sys.argv[1]) as z:
    for i in z.infolist():
        print(f"  {i.filename:<28} {i.file_size:>7} bytes")
    bad = z.testzip()
    print("  archive integrity:", "OK" if bad is None else f"CORRUPT at {bad}")
' "$OUT"
echo
echo "Upload $OUT to the grain-rot community on Thunderstore."
