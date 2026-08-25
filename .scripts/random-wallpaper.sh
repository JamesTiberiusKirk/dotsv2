#!/usr/bin/env bash
# Jump to a random wallpaper. Thin shim so the transition config lives in one
# place; kept as its own path because the host manifests symlink this name.
exec "$HOME/.scripts/menu/common/wallpaper.sh" --random
