#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS_DIR="$ROOT/installers/macos"
DIST="$MACOS_DIR/dist"
APP="$DIST/LocAlign Installer.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/payload"

# Info.plist
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleName</key>
    <string>LocAlign Installer</string>
    <key>CFBundleDisplayName</key>
    <string>LocAlign Installer</string>
    <key>CFBundleIdentifier</key>
    <string>org.localign.installer</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>LocAlignInstaller</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
  </dict>
</plist>
PLIST

# Launcher
cat > "$APP/Contents/MacOS/LocAlignInstaller" <<'SH'
#!/bin/zsh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DIR="$(cd "$APP_DIR/Resources/payload" && pwd)"
SCRIPT="$PAYLOAD_DIR/install.sh"

if [[ ! -f "$SCRIPT" ]]; then
  osascript -e 'display dialog "Missing installer script (install.sh)." buttons {"OK"} default button 1 with icon stop'
  exit 1
fi

chmod +x "$SCRIPT" 2>/dev/null || true
open -a Terminal "$SCRIPT"
exit 0
SH
chmod +x "$APP/Contents/MacOS/LocAlignInstaller"

# Payload
cp -R "$MACOS_DIR/payload/"* "$APP/Contents/Resources/payload/"
chmod +x "$APP/Contents/Resources/payload/install.sh"

# Zip
mkdir -p "$DIST"
cd "$DIST"
ditto -c -k --sequesterRsrc --keepParent "LocAlign Installer.app" "LocAlign-Installer-macOS.zip"
cd "$ROOT"

echo "Built:"
echo "  $APP"
echo "  $DIST/LocAlign-Installer-macOS.zip"
