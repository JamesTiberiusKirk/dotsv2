#!/bin/sh
# Install keyd config + init service (requires root).
# Detects runit vs systemd and sets up the service accordingly.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Must be run as root (use sudo)"
    exit 1
fi

REAL_USER="${SUDO_USER:-${USER:-}}"
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    echo "Cannot detect invoking user. Run via: sudo $0"
    exit 1
fi

USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "Could not resolve home directory for $REAL_USER"
    exit 1
fi

CONFIG_SRC="$USER_HOME/.config/keyd/default.conf"
CONFIG_DST="/etc/keyd/default.conf"

mkdir -p /etc/keyd
ln -sfn "$CONFIG_SRC" "$CONFIG_DST"
echo "Linked $CONFIG_DST -> $CONFIG_SRC"

if [ -d /run/runit/service ] || pgrep -x runsvdir >/dev/null 2>&1; then
    INIT=runit
elif [ -d /run/systemd/system ]; then
    INIT=systemd
else
    INIT=unknown
fi

case "$INIT" in
    runit)
        SV_SRC="$USER_HOME/.config/runit/sv/keyd"
        SV_DST="/etc/runit/sv/keyd"
        SV_ENABLE="/etc/runit/runsvdir/default/keyd"
        if [ ! -d "$SV_SRC" ]; then
            echo "WARN: $SV_SRC missing; skipping runit service setup."
        else
            ln -sfn "$SV_SRC" "$SV_DST"
            ln -sfn "$SV_DST" "$SV_ENABLE"
            echo "runit service enabled. Starts in ~5s via runsvdir."
            echo "Reload config: sv reload keyd"
        fi
        ;;
    systemd)
        systemctl enable --now keyd.service
        echo "systemd service enabled and started."
        echo "Reload config: systemctl reload keyd"
        ;;
    *)
        echo "WARN: unknown init system; service not configured."
        echo "Start keyd manually or add a service for your init."
        ;;
esac
