#!/bin/bash
# Builds the two .app bundles and a drag-and-drop DMG. Run via `make dmg`.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/dist
rm -rf "$OUT"; mkdir -p "$OUT"

make_app() { # name binary plist
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$2" "$app/Contents/MacOS/$(basename "$2")"
  cp "$3" "$app/Contents/Info.plist"
  codesign -s - -f --deep "$app"
}
make_app "iMac Display Sender"   build/sender   Packaging/Sender-Info.plist
make_app "iMac Display Receiver" build/receiver Packaging/Receiver-Info.plist

cp Packaging/DMG-README.txt "$OUT/READ ME FIRST.txt"

rm -f build/iMacDisplay.dmg
# makehybrid builds straight from the folder (no mounting needed); fall back to create.
hdiutil makehybrid -hfs -hfs-volume-name "iMac Display" -ov -o build/iMacDisplay.dmg "$OUT" >/dev/null 2>&1 \
  || hdiutil create -volname "iMac Display" -srcfolder "$OUT" -ov -format UDZO build/iMacDisplay.dmg >/dev/null
echo "Created build/iMacDisplay.dmg"
