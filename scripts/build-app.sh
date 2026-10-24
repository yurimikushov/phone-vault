#!/usr/bin/env bash
set -euo pipefail

# PhoneVault macOS App Bundle Builder
# Usage: ./scripts/build-app.sh [--debug|--release]

CONFIGURATION="release"
for arg in "$@"; do
    case "$arg" in
        --debug)
            CONFIGURATION="debug"
            ;;
        --release)
            CONFIGURATION="release"
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--debug|--release]"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building PhoneVaultApp ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

BIN_PATH="$REPO_ROOT/.build/$CONFIGURATION/PhoneVaultApp"
if [[ ! -f "$BIN_PATH" ]]; then
    # In some toolchain setups, the binary is under .build/arm64-apple-macosx/$CONFIGURATION
    BIN_PATH=$(find "$REPO_ROOT/.build" -type f -name "PhoneVaultApp" -perm +111 | grep -i "$CONFIGURATION" | head -n 1)
fi

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: PhoneVaultApp binary not found."
    exit 1
fi

APP_DIR="$REPO_ROOT/build/PhoneVault.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BIN_PATH" "$MACOS_DIR/PhoneVaultApp"
chmod +x "$MACOS_DIR/PhoneVaultApp"

# Create / copy AppIcon.icns
if [[ -f "$REPO_ROOT/resources/AppIcon.icns" ]]; then
    cp "$REPO_ROOT/resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [[ -f "$SCRIPT_DIR/generate-icon.swift" ]]; then
    echo "==> Generating AppIcon..."
    swift "$SCRIPT_DIR/generate-icon.swift" "$RESOURCES_DIR/AppIcon.icns"
fi

# Write Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PhoneVaultApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.phonevault.PhoneVault</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PhoneVault</string>
    <key>CFBundleDisplayName</key>
    <string>PhoneVault</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 PhoneVault. All rights reserved.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Write PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Ad-hoc sign the app bundle
echo "==> Signing application bundle..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

echo "==> Successfully created PhoneVault.app!"
echo "    Location: $APP_DIR"
echo "    Launch with: open \"$APP_DIR\""
