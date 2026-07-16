#!/usr/bin/env python3
"""Persist and restore Anker PowerConf C200 framing on macOS."""

from __future__ import annotations

import argparse
import configparser
import ctypes
import ctypes.util
import json
import os
import signal
import struct
import sys
import time
from pathlib import Path

VID = 0x291A
PID = 0x3369
UVC_UNIT = 0x01
UVC_INTERFACE = 0
VENDOR_UNIT = 0x06
CONFIG_DIR = Path.home() / "Library" / "Application Support" / "C200 Keeper"
STATE_FILE = CONFIG_DIR / "framing.json"
ANKER_STATE = Path.home() / "Library" / "Application Support" / "AnkerWork" / "datainfo_A3369.ini"


class CameraError(RuntimeError):
    pass


class C200:
    """Minimal libusb transport for the C200 controls used by AnkerWork."""

    def __init__(self) -> None:
        library = ctypes.util.find_library("usb-1.0") or "/opt/homebrew/lib/libusb-1.0.dylib"
        try:
            self.usb = ctypes.CDLL(library)
        except OSError as error:
            raise CameraError("libusb is missing; run: brew install libusb") from error
        self._declare_api()
        self.context = ctypes.c_void_p()
        if self.usb.libusb_init(ctypes.byref(self.context)) != 0:
            raise CameraError("Could not initialize libusb")
        raw_handle = self.usb.libusb_open_device_with_vid_pid(self.context, VID, PID)
        if not raw_handle:
            self.usb.libusb_exit(self.context)
            raise CameraError("Anker PowerConf C200 is not connected")
        self.handle = ctypes.c_void_p(raw_handle)

    def _declare_api(self) -> None:
        self.usb.libusb_init.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
        self.usb.libusb_open_device_with_vid_pid.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_uint16]
        self.usb.libusb_open_device_with_vid_pid.restype = ctypes.c_void_p
        self.usb.libusb_control_transfer.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint8,
            ctypes.c_uint16, ctypes.c_uint16, ctypes.POINTER(ctypes.c_ubyte), ctypes.c_uint16, ctypes.c_uint]
        self.usb.libusb_control_transfer.restype = ctypes.c_int

    def close(self) -> None:
        if getattr(self, "handle", None):
            self.usb.libusb_close(self.handle)
            self.handle = None
        if getattr(self, "context", None):
            self.usb.libusb_exit(self.context)
            self.context = None

    def __enter__(self) -> "C200":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _set(self, unit: int, selector: int, payload: bytes) -> None:
        data = (ctypes.c_ubyte * len(payload)).from_buffer_copy(payload)
        result = self.usb.libusb_control_transfer(self.handle, 0x21, 0x01, selector << 8,
            (unit << 8) | UVC_INTERFACE, data, len(payload), 1000)
        if result != len(payload):
            raise CameraError(f"USB control {selector:#x} failed ({result})")

    def set_fov(self, degrees: int) -> None:
        if degrees not in (65, 78, 95):
            raise ValueError("FoV must be 65, 78, or 95 degrees")
        payload = bytearray(60)
        payload[0:4] = struct.pack("<HH", 0x0100, degrees)
        self._set(VENDOR_UNIT, 0x10, payload)

    def set_zoom(self, value: int) -> None:
        if not 100 <= value <= 400:
            raise ValueError("Zoom must be between 100 (1x) and 400 (4x)")
        # AnkerWork writes four bytes, although the UVC value itself is uint16.
        self._set(UVC_UNIT, 0x0B, struct.pack("<I", value))

    def set_pan_tilt(self, pan: int, tilt: int) -> None:
        self._set(UVC_UNIT, 0x0D, struct.pack("<ii", pan, tilt))


def load_state() -> dict:
    if not STATE_FILE.exists():
        raise CameraError("No saved framing. Run capture after adjusting the camera in AnkerWork.")
    return json.loads(STATE_FILE.read_text())


def save_state(state: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(STATE_FILE)


def capture_anker_state() -> dict:
    if not ANKER_STATE.exists():
        raise CameraError(f"AnkerWork settings were not found at {ANKER_STATE}")
    parser = configparser.ConfigParser()
    parser.read(ANKER_STATE)
    section = parser["config"]
    frame_mode = section.getboolean("frameMode", fallback=False)
    state = {
        "mode": "angle-frame" if frame_mode else "fov",
        "zoom": section.getint("zoom", fallback=100),
        "pan": section.getint("pan", fallback=0),
        "tilt": section.getint("tilt", fallback=0),
        "fov": section.getint("fovValue", fallback=95),
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    save_state(state)
    return state


def apply_state(state: dict) -> None:
    with C200() as camera:
        if state["mode"] == "angle-frame":
            camera.set_pan_tilt(int(state["pan"]), int(state["tilt"]))
            camera.set_zoom(int(state["zoom"]))
        else:
            camera.set_fov(int(state["fov"]))


def run_daemon(interval: float) -> None:
    running = True

    def stop(*_: object) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    while running:
        try:
            apply_state(load_state())
        except (CameraError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            print(f"{time.strftime('%F %T')} {error}", file=sys.stderr, flush=True)
        end = time.monotonic() + interval
        while running and time.monotonic() < end:
            time.sleep(min(0.25, end - time.monotonic()))


def main() -> int:
    parser = argparse.ArgumentParser(description="Keep Anker PowerConf C200 framing from resetting")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("capture", help="save the current framing from AnkerWork")
    sub.add_parser("apply", help="restore saved framing now")
    sub.add_parser("status", help="show saved framing")
    zoom = sub.add_parser("set-zoom", help="save and immediately apply a zoom value")
    zoom.add_argument("value", type=int, help="100 (1x) through 400 (4x)")
    run = sub.add_parser("run", help="run the background keeper")
    run.add_argument("--interval", type=float, default=2.0)
    args = parser.parse_args()
    try:
        if args.command == "capture":
            state = capture_anker_state()
            apply_state(state)
            print(f"Saved {state['mode']} framing: zoom={state['zoom']}, pan={state['pan']}, tilt={state['tilt']}, fov={state['fov']}°")
        elif args.command == "apply":
            apply_state(load_state())
            print("Saved framing restored")
        elif args.command == "status":
            print(json.dumps(load_state(), indent=2))
        elif args.command == "set-zoom":
            if not 100 <= args.value <= 400:
                raise ValueError("Zoom must be between 100 and 400")
            state = load_state() if STATE_FILE.exists() else capture_anker_state()
            state.update(mode="angle-frame", zoom=args.value, captured_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            save_state(state)
            apply_state(state)
            print(f"Saved and applied zoom {args.value} ({args.value / 100:g}x)")
        else:
            run_daemon(args.interval)
    except (CameraError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"c200-keeper: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
