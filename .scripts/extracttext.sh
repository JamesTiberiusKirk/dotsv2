#!/bin/sh

# where to save screenshots
path=$HOME"/Pictures/screenshots"
mkdir -p "$path"

# timestamp + active window classname for filename
timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(hyprctl activewindow -j | grep -oP '"class"\s*:\s*"\K[^"]+')
out="${path}/${timestamp}-${active_window}-ocr.png"

# 1) grab a region via slurp → grim → $out
grim -g "$(slurp)" "$out"

# 2) copy the raw image to the clipboard (optional)
wl-copy < "$out"

# 3) OCR it and copy the plain-text result
tesseract "$out" stdout -l eng | wl-copy

# 4) notify you that it’s done
notify-send "OCR Complete" "Extracted text is now in your clipboard."
