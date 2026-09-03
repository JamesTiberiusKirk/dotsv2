#!/usr/bin/env python3
# Hyprland hotplug hook. There is no config event for it — monitoradded /
# monitorremoved only ever appear on the event socket, so without this daemon
# nothing on the system reacts to plugging a monitor in:
#   - monitor-layout.sh runs once at startup and never again, so a new output
#     lands wherever Hyprland auto-placed it
#   - awww registers the new output but paints it black; it never back-fills
#     the image it is already showing everywhere else
# Same socket2 idiom as workspace-layouts.sh. Autostarted from base.lua.
import os
import socket
import subprocess
import sys

HOME = os.path.expanduser("~")
LAYOUT = f"{HOME}/.config/hypr/scripts/monitor-layout.sh"
WALLPAPER = f"{HOME}/.scripts/menu/common/wallpaper.sh"

# Hyprland emits both monitoradded and monitoraddedv2 for one plug, and the
# layout apply itself moves outputs around; the debounce below collapses the
# burst into a single reaction.
DEBOUNCE = 0.5


def react():
    subprocess.run([LAYOUT], timeout=15)
    # --current re-applies the wallpaper in use to every output, cold (no
    # transition), which is the only way the new one stops being black
    subprocess.run([WALLPAPER, "--current"], timeout=30)


def main():
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not his:
        return 1
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(f"{runtime}/hypr/{his}/.socket2.sock")

    buf = b""
    pending = False
    while True:
        try:
            # blocks until the next event, then waits out the burst
            s.settimeout(DEBOUNCE if pending else None)
            chunk = s.recv(4096)
            if not chunk:
                break
        except socket.timeout:
            pending = False
            try:
                react()
            except Exception:
                pass
            continue
        except InterruptedError:
            continue
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line.startswith(b"monitoradded") or line.startswith(b"monitorremoved"):
                pending = True
    return 0


if __name__ == "__main__":
    sys.exit(main())
