#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="build/Notchbeat.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset
# Universal binary: runs on Apple Silicon and Intel Macs.
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o build/Notchbeat-arm64
swiftc -O -swift-version 5 -target x86_64-apple-macos14.0 Sources/*.swift -o build/Notchbeat-x86_64
lipo -create build/Notchbeat-arm64 build/Notchbeat-x86_64 -output "$APP/Contents/MacOS/Notchbeat"
cp Resources/Info.plist "$APP/Contents/"
swift Resources/make_icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [[ "$1" == "install" ]]; then
  pkill -x Notchbeat || true
  pkill -x YTMusicIsland || true                 # old name
  rm -rf "/Applications/Notchbeat.app" "/Applications/YT Music Island.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications"
fi
if [[ "$1" == "share" ]]; then
  OUT="$HOME/Desktop/Notchbeat"
  rm -rf "$OUT" "$HOME/Desktop/Notchbeat.zip"
  mkdir -p "$OUT"
  ditto "$APP" "$OUT/Notchbeat.app"
  cp Resources/README.txt "$OUT/How to install.txt"
  (cd "$HOME/Desktop" && ditto -c -k --sequesterRsrc --keepParent Notchbeat Notchbeat.zip)
  echo "Share folder: $OUT"
  echo "Zip: $HOME/Desktop/Notchbeat.zip"
fi
