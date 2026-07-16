# C200 Keeper

C200 Keeper is a small, open-source macOS utility that remembers the framing of an **Anker PowerConf C200** webcam and restores it when the camera resets or reconnects.

It includes a native Mac control window and menu-bar item with these actions:

- Save the current AnkerWork configuration
- Apply the saved configuration immediately
- Enable automatic re-application
- Disable automatic re-application
- Start the menu app automatically at login

> [!IMPORTANT]
> This project currently supports **macOS only** and specifically targets the PowerConf C200 USB identifier `291a:3369`. It is an independent community project and is not affiliated with or endorsed by Anker.

## Why this exists

The C200 can lose its field-of-view or custom Angle & Frame settings when it is reconnected, reset, or opened by another application. C200 Keeper stores the desired configuration on the Mac and periodically sends it back to the camera.

## Requirements

- macOS 13 or later for the menu application
- Anker PowerConf C200
- [AnkerWork](https://www.ankerwork.com/download-software) for visually choosing the initial framing
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3
- libusb (`brew install libusb`)

The command-line keeper itself may work on older macOS versions, but the packaged UI targets macOS 13 or later.

## Install

Clone the repository, then run:

```sh
git clone https://github.com/YOUR-USERNAME/c200-keeper.git
cd c200-keeper
./install.sh
```

The installer builds the native application, installs it in `/Applications` (or `~/Applications` when necessary), captures the most recent AnkerWork framing, enables both background restoration and start-at-login, and opens the app.

If Homebrew is installed but libusb is missing:

```sh
brew install libusb
```

## Usage

1. Open AnkerWork.
2. Select the C200 and configure either a FoV preset or **Angle & Frame**.
3. Close AnkerWork so it does not compete for camera controls.
4. Open C200 Keeper and click **Save Current Config**.
5. Leave **Auto re-apply** enabled.

At login, C200 Keeper starts quietly. Opening it from Applications brings up the control window.

### Command line

The underlying keeper can also be used without the UI:

```sh
./c200_keeper.py capture
./c200_keeper.py apply
./c200_keeper.py status
./c200_keeper.py set-zoom 175
./c200_keeper.py run --interval 2
```

Zoom uses the camera's native range: `100` is 1× and `400` is 4×.

## Saved data and logs

- Configuration: `~/Library/Application Support/C200 Keeper/framing.json`
- Logs: `~/Library/Logs/C200 Keeper/`
- Background worker: `~/Library/LaunchAgents/com.local.c200-keeper.plist`
- Login launcher: `~/Library/LaunchAgents/com.local.c200-keeper-menu-login.plist`

No camera images or video are captured. The utility only sends USB camera-control values.

## Uninstall

```sh
./uninstall.sh
```

The saved framing is retained by default. To remove it too:

```sh
./uninstall.sh --purge
```

## Development

Build the app without installing it:

```sh
./build_menu_app.sh
open "build/C200 Keeper.app"
```

Run the tests:

```sh
python3 -m unittest -v
```

Project layout:

```text
MenuApp/                    Native AppKit menu/window application
c200_keeper.py              USB control, persistence, and daemon
build_menu_app.sh           Reproducible local app build
install.sh                  User-level installer
uninstall.sh                Service and application removal
*.plist.template            macOS LaunchAgent templates
test_c200_keeper.py         Unit tests using a fake camera backend
```

## How it works

The C200 exposes standard UVC pan, tilt, and zoom controls, plus a vendor extension for its 65°, 78°, and 95° FoV presets. C200 Keeper uses libusb control transfers without opening the video stream.

AnkerWork's last configuration is read from its local `datainfo_A3369.ini` file only when **Save Current Config** is selected. Automatic restoration then uses C200 Keeper's own JSON copy, preventing a camera reset from being mistaken for a newly chosen preference.

## Limitations

- Do not leave AnkerWork running after saving; simultaneous control writes can conflict.
- Only the C200 USB ID `291a:3369` has been tested.
- A Windows version would require a separate system-tray and USB backend.
- The app is ad-hoc signed for local use, not notarized through the Apple Developer Program.

## Contributing

Bug reports and pull requests are welcome. Please include your macOS version, C200 firmware version, whether FoV or Angle & Frame mode was used, and relevant error-log lines. Do not include serial numbers or other private identifiers.

## License

MIT. See [LICENSE](LICENSE).
