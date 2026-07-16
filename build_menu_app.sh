#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
APP="$BUILD/C200 Keeper.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
xcrun swiftc -O -framework AppKit "$ROOT/MenuApp/main.swift" -o "$CONTENTS/MacOS/C200 Keeper"
cp "$ROOT/c200_keeper.py" "$ROOT/README.md" "$CONTENTS/Resources/"

sed "s/__VERSION__/1.0.0/g" "$ROOT/MenuApp/Info.plist.template" > "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
echo "$APP"
