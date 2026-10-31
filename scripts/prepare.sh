#!/usr/bin/env bash
# Fetches Actual Budget at the pinned commit into ./actual, applies our
# patches, and rebrands the iOS app (name + bundle ID).
#
# Usage: scripts/prepare.sh            (run from anywhere)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../app.config
source "$ROOT/app.config"

SRC="$ROOT/actual"
MOBILE="$SRC/packages/mobile-client"

echo "==> Fetching Actual at $ACTUAL_REF"
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" remote add origin "$ACTUAL_REPO"
git -C "$SRC" fetch -q --depth 1 origin "$ACTUAL_REF"
git -C "$SRC" checkout -q FETCH_HEAD

echo "==> Applying patches"
shopt -s nullglob
for patch in "$ROOT"/patches/*.patch; do
  echo "    $(basename "$patch")"
  git -C "$SRC" apply --whitespace=nowarn "$patch"
done
shopt -u nullglob

echo "==> Branding: \"$APP_NAME\" ($BUNDLE_ID)"
# iOS bundle ID (Debug + Release build settings).
sed -i.bak -E "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/g" \
  "$MOBILE/ios/App/App.xcodeproj/project.pbxproj"
# Capacitor app ID + name.
sed -i.bak -E \
  -e "s/appId: '[^']*'/appId: '$BUNDLE_ID'/" \
  -e "s/appName: '[^']*'/appName: '$APP_NAME'/" \
  "$MOBILE/capacitor.config.ts"
# Home Screen name.
PLIST="$MOBILE/ios/App/App/Info.plist"
python3 - "$PLIST" "$APP_NAME" <<'PY'
import plistlib, sys
path, name = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    data = plistlib.load(f)
data["CFBundleDisplayName"] = name
with open(path, "wb") as f:
    plistlib.dump(data, f)
PY
find "$MOBILE" -name '*.bak' -delete

# Export straight to App Store Connect (TestFlight) instead of to a local .ipa.
cat > "$MOBILE/ios/App/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

# Our own assets (e.g. a custom app icon) overwrite Actual's when present.
if [ -d "$ROOT/overrides" ]; then
  echo "==> Copying overrides"
  cp -R "$ROOT/overrides/." "$SRC/"
fi

echo "==> Ready in $SRC"
