#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
native_configuration="${1:-Release}"
case "$native_configuration" in Debug|Release) ;; *) echo "Usage: $0 [Debug|Release]" >&2; exit 2 ;; esac
native_xcode_major="$(xcodebuild -version | awk 'NR==1 { split($2, parts, "."); print parts[1] }')"
if [ "$native_xcode_major" -lt 27 ]; then
  echo "Xcode 27 or later is required for the macOS 27 APIs." >&2
  exit 1
fi
xcodebuild -project "$native_root/QuietGlyph.xcodeproj" -scheme QuietGlyph \
  -configuration "$native_configuration" -derivedDataPath "$native_root/DerivedData" build
