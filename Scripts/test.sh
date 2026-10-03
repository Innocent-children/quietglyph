#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")/.." && pwd)"
native_mode="${1:-unit}"
native_arguments=(-project "$native_root/Inkline.xcodeproj" -scheme Inkline
  -configuration Debug -derivedDataPath "$native_root/DerivedData"
  -destination "platform=macOS,arch=$(uname -m)" -parallel-testing-enabled NO)
case "$native_mode" in
  unit) native_arguments+=(-only-testing:InklineTests) ;;
  ui) native_arguments+=(-only-testing:InklineUITests) ;;
  all) ;;
  *) echo "Usage: $0 [unit|ui|all]" >&2; exit 2 ;;
esac
xcodebuild "${native_arguments[@]}" test
