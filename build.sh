#!/bin/sh
set -eu
cd "$(dirname "$0")"

HOME_DIR="$HOME/Library/Application Support/TernNotch"
OUT="$HOME_DIR/TernNotch.app"
STAGE="$HOME_DIR/.TernNotch.app.$$"
mkdir -p build "$HOME_DIR"

FLAGS=""
CLT_SWIFT="$(xcode-select -p)/usr/include/swift"
if [ -f "$CLT_SWIFT/module.modulemap" ] && [ -f "$CLT_SWIFT/bridging.modulemap" ]; then
	: >build/empty.modulemap
	cat >build/clt-overlay.yaml <<EOF
{"version": 0, "case-sensitive": "false", "roots": [{"type": "directory", "name": "$CLT_SWIFT",
  "contents": [{"type": "file", "name": "module.modulemap", "external-contents": "$PWD/build/empty.modulemap"}]}]}
EOF
	FLAGS="-vfsoverlay build/clt-overlay.yaml -Xcc -ivfsoverlay -Xcc build/clt-overlay.yaml"
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS"
cp app/Info.plist "$STAGE/Contents/Info.plist"
mkdir -p "$STAGE/Contents/Resources"
cp app/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -swift-version 5 $FLAGS \
	-target "$(uname -m)-apple-macos14.0" \
	-o "$STAGE/Contents/MacOS/TernNotch" \
	app/Sources/*.swift
xattr -cr "$STAGE"
codesign --force --sign - "$STAGE"
rm -rf "$OUT"
mv "$STAGE" "$OUT"
echo "built $OUT"
