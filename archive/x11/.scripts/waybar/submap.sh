#!/usr/bin/env python3
import json
import os
import socket
import sys


def emit(name):
    payload = {"text": name.upper(), "class": "active"} if name else {"text": "", "class": ""}
    print(json.dumps(payload), flush=True)


def main():
    his = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not his:
        return 0
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sock_path = f"{runtime}/hypr/{his}/.socket2.sock"

    emit("")

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
            if line.startswith(b"submap>>"):
                name = line[len(b"submap>>"):].decode("utf-8", "replace")
                emit(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
