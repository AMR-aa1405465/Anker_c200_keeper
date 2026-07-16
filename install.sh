#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_NAME="C200 Keeper.app"
if [ -z "${INSTALL_DIR:-}" ]; then
    if [ -w /Applications ]; then
        INSTALL_DIR=/Applications
    else
        INSTALL_DIR="$HOME/Applications"
    fi
fi
APP="$INSTALL_DIR/$APP_NAME"
WORKER_LABEL=com.local.c200-keeper
LOGIN_LABEL=com.local.c200-keeper-menu-login
PYTHON=$(command -v python3 || true)

reload_agent() {
    label=$1
    plist=$2
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    attempts=0
    while launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 && [ "$attempts" -lt 20 ]; do
        sleep 0.1
        attempts=$((attempts + 1))
    done
    attempts=0
    until launchctl bootstrap "gui/$(id -u)" "$plist"; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 3 ]; then
            echo "Could not start $label" >&2
            return 1
        fi
        sleep 0.5
    done
}

if [ -z "$PYTHON" ]; then
    echo "Python 3 is required." >&2
    exit 1
fi
if ! "$PYTHON" -c 'import ctypes; ctypes.CDLL("/opt/homebrew/lib/libusb-1.0.dylib")' 2>/dev/null && \
   ! "$PYTHON" -c 'import ctypes, ctypes.util; assert ctypes.util.find_library("usb-1.0")' 2>/dev/null; then
    echo "libusb is required. Install it with: brew install libusb" >&2
    exit 1
fi

"$ROOT/build_menu_app.sh" >/dev/null
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/C200 Keeper"
rm -rf "$APP"
ditto "$ROOT/build/$APP_NAME" "$APP"

WORKER_AGENT="$HOME/Library/LaunchAgents/$WORKER_LABEL.plist"
sed -e "s|__PYTHON__|$PYTHON|g" \
    -e "s|__SCRIPT__|$APP/Contents/Resources/c200_keeper.py|g" \
    -e "s|__HOME__|$HOME|g" "$ROOT/launchagent.plist.template" > "$WORKER_AGENT"

LOGIN_AGENT="$HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"
ESCAPED_APP=$(printf '%s' "$APP" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
sed "s|__APP_PATH__|$ESCAPED_APP|g" "$ROOT/loginagent.plist.template" > "$LOGIN_AGENT"

"$PYTHON" "$APP/Contents/Resources/c200_keeper.py" capture
reload_agent "$WORKER_LABEL" "$WORKER_AGENT"
reload_agent "$LOGIN_LABEL" "$LOGIN_AGENT"
open -a "$APP"

echo "C200 Keeper installed at: $APP"
