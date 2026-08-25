#!/bin/sh

path=$HOME"/Pictures/screenshots"
mkdir -p "$path"
timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(xdotool getactivewindow getwindowclassname 2>/dev/null || echo "unknown")
out="${path}/${timestamp}-${active_window}-ocr.png"

# Capture region with maim (waits for selection)
maim -s "$out"

# Check if screenshot was actually taken (user might have cancelled)
if [ ! -f "$out" ]; then
    notify-send "OCR Cancelled" "No screenshot taken."
    exit 1
fi

# Copy image to clipboard
xclip -selection clipboard -t image/png < "$out"

# OCR and copy text
extracted_text=$(tesseract "$out" stdout -l eng 2>/dev/null)

if [ -n "$extracted_text" ]; then
    echo "$extracted_text" | xclip -selection clipboard
    notify-send "OCR Complete" "Extracted text is now in your clipboard."
else
    notify-send "OCR Failed" "No text could be extracted."
fi
