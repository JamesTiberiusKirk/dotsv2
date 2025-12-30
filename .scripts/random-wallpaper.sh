#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Pictures/wallpapers/"
CURRENT_WALL=$(hyprctl hyprpaper listloaded)

# Get a random wallpaper that is not the current one
# WALLPAPER=$(find "$WALLPAPER_DIR" -type f ! -name "$(basename "$CURRENT_WALL")" | shuf -n 1)

WALLPAPER=$(find "$WALLPAPER_DIR" -type f \
    ! -name "$(basename "$CURRENT_WALL")" \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \
       -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o -iname "*.svg" \) \
    | shuf -n 1)

# Apply the selected wallpaper
hyprctl hyprpaper reload ,"$WALLPAPER"
