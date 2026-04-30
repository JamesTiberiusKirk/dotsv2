#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys


def find_title(monitor_name):
    try:
        monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"]))
        clients = json.loads(subprocess.check_output(["hyprctl", "-j", "clients"]))
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return ""
    mon = next((m for m in monitors if m.get("name") == monitor_name), None)
    if mon is None:
        return ""
    active_ws_id = mon.get("activeWorkspace", {}).get("id")
    visible = [
        c for c in clients
        if c.get("workspace", {}).get("id") == active_ws_id
        and c.get("mapped", True)
        and not c.get("hidden", False)
        and c.get("title")
    ]
    if not visible:
        return ""
    visible.sort(key=lambda c: c.get("focusHistoryID", 999999))
    return visible[0].get("title", "")


def main():
    monitor = os.environ.get("WAYBAR_OUTPUT_NAME", "")
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not monitor or not his:
        return 0
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sock_path = f"{runtime}/hypr/{his}/.socket2.sock"

    last = None

    def emit():
        nonlocal last
        title = find_title(monitor)
        if title != last:
            last = title
            print(title, flush=True)

    emit()

    relevant = (
        b"activewindow>>", b"activewindowv2>>",
        b"focusedmon>>",
        b"workspace>>", b"workspacev2>>",
        b"openwindow>>", b"closewindow>>",
        b"movewindow>>", b"movewindowv2>>",
        b"windowtitle>>", b"windowtitlev2>>",
        b"changefloatingmode>>",
    )
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    buf = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if any(line.startswith(e) for e in relevant):
                emit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
