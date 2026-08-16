#!/usr/bin/env bash
# Fetch the wallpaper collection into ~/Pictures/wallpapers.
# Paintings: Wikimedia Commons (public domain classical landscapes).
# Photos: wallhaven.cc toplist (SFW, >= 2560x1440).
# Skips files that already exist — safe to re-run on any host.
set -u

DIR="$HOME/Pictures/wallpapers"
mkdir -p "$DIR"

get() { # name url
    if [ -s "$DIR/$1.jpg" ]; then
        echo "skip $1"
        return
    fi
    if curl -sfL "$2" -o "/tmp/wall-dl-$1" \
        && magick "/tmp/wall-dl-$1" -resize '3840x2160>' -quality 88 "$DIR/$1.jpg"; then
        identify -format "got %f %wx%h\n" "$DIR/$1.jpg"
    else
        echo "FAILED $1"
    fi
    rm -f "/tmp/wall-dl-$1"
}

# --- Classical landscapes (Commons originals) ---
get friedrich-wanderer      "https://upload.wikimedia.org/wikipedia/commons/b/b9/Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg"
get friedrich-abbey         "https://upload.wikimedia.org/wikipedia/commons/3/32/Caspar_David_Friedrich_-_Abtei_im_Eichwald_-_Google_Art_Project.jpg"
get shishkin-pine-forest    "https://upload.wikimedia.org/wikipedia/commons/1/1e/Shishkin%2C_Ivan_-_Morning_in_a_Pine_Forest.jpg"
get bierstadt-sierra-nevada "https://upload.wikimedia.org/wikipedia/commons/5/5c/Albert_Bierstadt_-_Among_the_Sierra_Nevada%2C_California_-_Google_Art_Project.jpg"
get cole-oxbow              "https://upload.wikimedia.org/wikipedia/commons/b/b1/Cole_Thomas_The_Oxbow_%28The_Connecticut_River_near_Northampton_1836%29.jpg"

# --- Nature photography (wallhaven toplist) ---
for q in mountain forest nature; do
    curl -sf "https://wallhaven.cc/api/v1/search" --get \
        --data-urlencode "q=$q" \
        --data-urlencode "categories=100" \
        --data-urlencode "purity=100" \
        --data-urlencode "sorting=toplist" \
        --data-urlencode "atleast=2560x1440" \
        | jq -r '.data[:2][] | "\(.id) \(.path)"'
done | while read -r id path; do
    get "wallhaven-$id" "$path"
done
