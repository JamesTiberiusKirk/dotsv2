#!/bin/sh

path=$HOME"/Pictures/screenshots/"
mkdir -p "$path"

# Flameshot GUI (saves to configured path, copies to clipboard)
flameshot gui --path "$path"
