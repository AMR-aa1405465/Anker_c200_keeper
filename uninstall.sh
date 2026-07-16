#!/bin/sh
set -eu

WORKER_LABEL=com.local.c200-keeper
LOGIN_LABEL=com.local.c200-keeper-menu-login
launchctl bootout "gui/$(id -u)/$WORKER_LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LOGIN_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$WORKER_LABEL.plist"
rm -f "$HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"
rm -rf "$HOME/Applications/C200 Keeper.app"
if [ -w /Applications ]; then
    rm -rf "/Applications/C200 Keeper.app"
fi

if [ "${1:-}" = "--purge" ]; then
    rm -rf "$HOME/Library/Application Support/C200 Keeper"
    rm -rf "$HOME/Library/Logs/C200 Keeper"
    echo "C200 Keeper and its saved data were removed."
else
    echo "C200 Keeper was removed. Saved framing was kept."
fi
