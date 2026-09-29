#!/bin/bash
set -euo pipefail
if [ "$#" -ne 1 ]; then echo "Usage: $0 /path/to/QuietGlyph.app" >&2; exit 2; fi
native_app="$1"
native_binary="$native_app/Contents/MacOS/QuietGlyph"
if [ ! -f "$native_binary" ]; then echo "Application executable is missing." >&2; exit 1; fi
native_arches="$(lipo -archs "$native_binary")"
if [[ " $native_arches " != *" arm64 "* ]] || [[ " $native_arches " != *" x86_64 "* ]]; then
  echo "Expected arm64 and x86_64, found: $native_arches" >&2
  exit 1
fi
native_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$native_app/Contents/Info.plist")"
if [ "$native_minimum" != "15.0" ]; then echo "Unexpected deployment target: $native_minimum" >&2; exit 1; fi
for native_file in "$native_app"/Contents/MacOS/*; do
  if /usr/bin/file "$native_file" | grep -q 'Mach-O'; then
    native_dependencies="$(otool -L "$native_file")"
    if printf '%s\n' "$native_dependencies" | grep -Ei 'Qt[0-9A-Za-z]*\.|QScintilla|Scintilla|Lexilla|Electron|Chromium'; then
      echo "A non-native runtime dependency was found." >&2
      exit 1
    fi
  fi
done
codesign --verify --deep --strict "$native_app"
printf 'Verified architectures: %s\nMinimum macOS: %s\n' "$native_arches" "$native_minimum"
