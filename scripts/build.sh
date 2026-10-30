#!/bin/zsh
# Builds build/SleepManager.app (release, ad-hoc signed). Needs only the Command Line Tools.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
app=build/SleepManager.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/*.svg "$app/Contents/Resources/"
cp "$(swift build -c release --show-bin-path)/SleepManager" "$app/Contents/MacOS/SleepManager"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SleepManager</string>
    <key>CFBundleIdentifier</key><string>local.sleep-manager</string>
    <key>CFBundleName</key><string>Sleep Manager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app"
