#!/usr/bin/env python3
import json
import os
import signal
import socket
import subprocess
import sys
import time

STATE_DIR = os.path.expanduser("~/.local/state/hypr")
STATE_FILE = os.path.join(STATE_DIR, "ws-layouts.json")
PID_FILE = "/tmp/hypr-ws-layouts.pid"


def get_his():
    return os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")


def get_socket_path():
    his = get_his()
    if not his:
        return ""
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return f"{runtime}/hypr/{his}/.socket2.sock"


def load_state():
    default = {"default": "dwindle", "overrides": {}}
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except Exception:
            pass
    return default


def save_state(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def get_current_workspace():
    try:
        r = subprocess.run(
            ["hyprctl", "activeworkspace", "-j"],
            capture_output=True, text=True, timeout=2,
        )
        return json.loads(r.stdout).get("id")
    except Exception:
        return None


def get_layout_for_ws(state, ws_id):
    return state.get("overrides", {}).get(str(ws_id), state.get("default", "dwindle"))


def apply_layout(layout):
    subprocess.run(
        ["hyprctl", "keyword", "general:layout", layout],
        capture_output=True, timeout=2,
    )


def handle_signal(signum, frame):
    state = load_state()
    ws = get_current_workspace()
    if ws is not None:
        apply_layout(get_layout_for_ws(state, ws))


def handle_event(line, state):
    if line.startswith(b"workspace>>"):
        ws_id = line[len(b"workspace>>"):]
        try:
            ws_id = int(ws_id)
        except ValueError:
            return
        apply_layout(get_layout_for_ws(state, ws_id))
    elif line.startswith(b"focusedmon>>"):
        parts = line[len(b"focusedmon>>"):].split(b",")
        if len(parts) >= 2:
            try:
                ws_id = int(parts[1])
                apply_layout(get_layout_for_ws(state, ws_id))
            except ValueError:
                pass


def poll_loop(state):
    last_ws = None
    while True:
        ws = get_current_workspace()
        if ws is not None and ws != last_ws:
            apply_layout(get_layout_for_ws(state, ws))
            last_ws = ws
        time.sleep(0.5)


def main():
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    state = load_state()
    if not os.path.exists(STATE_FILE):
        save_state(state)

    ws = get_current_workspace()
    if ws is not None:
        apply_layout(get_layout_for_ws(state, ws))

    signal.signal(signal.SIGUSR1, handle_signal)

    sock_path = get_socket_path()
    if not sock_path:
        poll_loop(state)
        return

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(None)
    s.connect(sock_path)

    buf = b""
    while True:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                handle_event(line, state)
        except InterruptedError:
            continue
        except Exception:
            break


if __name__ == "__main__":
    sys.exit(main())
