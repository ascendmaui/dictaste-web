#!/bin/bash
# Install FlowDictate to /Applications with a stable Apple Development signature.
# Do NOT ad-hoc re-sign after copy — that breaks Accessibility TCC every rebuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/build/Build/Products/Release/FlowDictate.app"
APP_DST="/Applications/FlowDictate.app"

cd "$ROOT"
xcodebuild -project FlowDictate.xcodeproj -scheme FlowDictate -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=L85AF3V872 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES

pkill -x FlowDictate 2>/dev/null || true
sleep 0.4
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

echo "Installed:"
codesign -dv --verbose=2 "$APP_DST" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier'
open "$APP_DST"
echo "Done. If Accessibility is off, enable FlowDictate for $APP_DST then use Relaunch in setup."
