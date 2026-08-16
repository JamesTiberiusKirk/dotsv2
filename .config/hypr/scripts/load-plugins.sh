#!/usr/bin/env bash
# Load hyprpm plugins (hyprglass), then re-evaluate the config.
# plugins.lua guards on hl.plugin.hyprglass, which is only true once the .so
# is loaded — so the config must reload *after* hyprpm or the whole glass
# block (incl. the fullscreen-disable rule) is silently skipped at startup.
set -u

hyprpm reload >/dev/null 2>&1 || exit 0
hyprctl reload >/dev/null
