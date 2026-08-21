#!/bin/sh
# Pseudotile toggle that sizes the window to 60% x 100% of the monitor on entry.
# Sizes are computed from the focused monitor at press time, so they scale
# across monitors. Hyprland 0.56 exposes pseudo state nowhere (neither IPC json
# nor HL.Window), so track it per window address; this bind is the only way
# pseudo gets toggled.
addr=$(hyprctl activewindow -j | sed -n 's/.*"address": "\(0x[0-9a-f]*\)".*/\1/p')
[ -n "$addr" ] || exit 0
state="${XDG_RUNTIME_DIR:-/tmp}/hypr-pseudo-$addr"
hyprctl dispatch 'hl.dsp.window.pseudo()'
if [ -e "$state" ]; then
    rm -f "$state" # left pseudo; resizing now would mangle the tiling split
else
    : > "$state"
    hyprctl eval 'local m=hl.get_active_monitor() local w,h=m.width,m.height if m.transform%2==1 then w,h=h,w end hl.dispatch(hl.dsp.window.resize({x=math.floor(w/m.scale*0.6),y=math.floor(h/m.scale)}))'
fi
