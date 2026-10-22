#!/bin/bash
# Builds build/Isola.app.
#   UNIVERSAL=1   arm64 + x86_64
#   VERSION=1.2.0 stamps the version into Info.plist (BUILD_NUMBER sets the build number, default 1)
#   ZIP=1         also writes build/Isola-macOS.zip, ready to share
#   DMG=1         also writes build/Isola-macOS.dmg, the installer: open it and drag Isola to Applications
set -euo pipefail
cd "$(dirname "$0")"

ADAPTER_COMMIT="797729d9b16316dc313844476c153d7a107ca0df"
ADAPTER_SRC=".adapter-src"
APP="build/Isola.app"
ADAPTER_OUT="$APP/Contents/Resources/Adapter"

build_adapter() {
    if [ ! -f "$ADAPTER_SRC/bin/mediaremote-adapter.pl" ]; then
        rm -rf "$ADAPTER_SRC"
        mkdir -p "$ADAPTER_SRC"
        curl -fsSL "https://github.com/ungive/mediaremote-adapter/archive/$ADAPTER_COMMIT.tar.gz" \
            | tar -xz -C "$ADAPTER_SRC" --strip-components=1
    fi

    local fw="$ADAPTER_OUT/MediaRemoteAdapter.framework"
    mkdir -p "$fw/Versions/A/Resources"

    clang -dynamiclib -fobjc-arc -fvisibility=default \
        -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
        -I "$ADAPTER_SRC/include" -I "$ADAPTER_SRC/src" \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
        -o "$fw/Versions/A/MediaRemoteAdapter" \
        "$ADAPTER_SRC"/src/adapter/{env,get,globals,keys,now_playing,repeat,seek,send,shuffle,speed,stream,test}.m \
        "$ADAPTER_SRC/src/private/MediaRemote.m" \
        "$ADAPTER_SRC"/src/utility/{Debounce,helpers}.m

    cp Resources/AdapterInfo.plist "$fw/Versions/A/Resources/Info.plist"
    ln -sfn A "$fw/Versions/Current"
    ln -sfn Versions/Current/MediaRemoteAdapter "$fw/MediaRemoteAdapter"
    ln -sfn Versions/Current/Resources "$fw/Resources"
    codesign --force --sign - "$fw"

    clang -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
        -I "$ADAPTER_SRC/src/test" \
        -framework Foundation -framework MediaPlayer \
        -o "$ADAPTER_OUT/MediaRemoteAdapterTestClient" \
        "$ADAPTER_SRC/src/test/main.m" "$ADAPTER_SRC/src/test/NowPlayingTest.m"
    codesign --force --sign - "$ADAPTER_OUT/MediaRemoteAdapterTestClient"

    cp "$ADAPTER_SRC/bin/mediaremote-adapter.pl" "$ADAPTER_OUT/"
    cp "$ADAPTER_SRC/LICENSE" "$ADAPTER_OUT/LICENSE-mediaremote-adapter"
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    for ARCH in arm64 x86_64; do
        swift build -c release --triple "$ARCH-apple-macosx14.0" --scratch-path ".build-$ARCH"
    done
    lipo -create \
        ".build-arm64/arm64-apple-macosx/release/Isola" \
        ".build-x86_64/x86_64-apple-macosx/release/Isola" \
        -output "$APP/Contents/MacOS/Isola"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Isola" "$APP/Contents/MacOS/Isola"
fi

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns Resources/MenuIcon.png Resources/MenuIcon@2x.png "$APP/Contents/Resources/"

if ! build_adapter; then
    echo "Warning: could not build the media adapter. Isola will only see Music and Spotify."
    rm -rf "$ADAPTER_OUT"
fi

codesign --force --sign - "$APP"

if [ "${ZIP:-0}" = "1" ]; then
    rm -f build/Isola-macOS.zip
    ditto -c -k --keepParent "$APP" build/Isola-macOS.zip
    echo "Zipped build/Isola-macOS.zip"
fi

if [ "${DMG:-0}" = "1" ]; then
    # The installer window, laid out by dmgbuild (dmg_settings.py) in a virtualenv of its own. Without it (it needs
    # Python 3.10 or later), a plain disk image.
    rm -f build/Isola-macOS.dmg
    VENV=".dmgbuild-venv"
    if [ ! -x "$VENV/bin/dmgbuild" ]; then
        rm -rf "$VENV"
        python3 -m venv "$VENV" && "$VENV/bin/pip" install -q "dmgbuild>=1.6,<2" || rm -rf "$VENV"
    fi
    if [ -x "$VENV/bin/dmgbuild" ]; then
        "$VENV/bin/dmgbuild" -s dmg_settings.py -D app="$APP" Isola build/Isola-macOS.dmg
    else
        echo "Warning: could not set up dmgbuild, so the disk image is a plain one."
        STAGE="build/dmg"
        rm -rf "$STAGE"
        mkdir -p "$STAGE"
        ditto "$APP" "$STAGE/Isola.app"
        ln -s /Applications "$STAGE/Applications"
        hdiutil create -volname Isola -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Isola-macOS.dmg >/dev/null
        rm -rf "$STAGE"
    fi
    echo "Wrote build/Isola-macOS.dmg"
fi

echo "Built $APP"
echo "Run it with: open $APP"
