#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" != "--no-build" ]; then bash "$native_root/Scripts/build.sh" Release; fi
native_app="$native_root/DerivedData/Build/Products/Release/Inkline.app"
bash "$native_root/Scripts/check-dependencies.sh" "$native_app"
mkdir -p "$native_root/dist"
native_stage="$(mktemp -d "$native_root/dist/package.XXXXXX")"
trap 'rm -rf "$native_stage"' EXIT
ditto "$native_app" "$native_stage/Inkline.app"
cp "$native_root/LICENSE" "$native_stage/LICENSE"
ln -s /Applications "$native_stage/Applications"
native_output="$native_root/dist/Inkline-macOS.dmg"
hdiutil create -volname "Inkline" -srcfolder "$native_stage" -ov -format UDZO "$native_output"
printf 'Created %s\n' "$native_output"
