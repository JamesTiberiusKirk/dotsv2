# Hyprland → i3wm + Xorg Migration Plan

## Current Setup Analysis

### Existing Configuration
- **Compositor**: Hyprland (Wayland)
- **Terminal**: Alacritty
- **Launcher**: Wofi
- **Notifications**: Dunst (works on both!)
- **File Manager**: Caja
- **Status Bar**: Waybar
- **Screenshot**: grim + slurp + wl-copy
- **Autostart**: waybar, dunst, pasystray, owncloud, hyprland-autoname-workspaces, blueman-applet, hyprpaper
- **System**: Arch Linux with pacman/yay

---

## Tool Migration Map

| Current (Wayland)                 | →   | X11 Alternative                    | Notes                                  |
| --------------------------------- | --- | ---------------------------------- | -------------------------------------- |
| **wofi**                          | →   | **dmenu**                          | Already installed, classic i3 launcher |
| **waybar**                        | →   | **i3status**                       | Per your choice, lightweight           |
| **grim + slurp**                  | →   | **flameshot**                      | GUI screenshot tool for X11            |
| **wl-copy/wl-paste**              | →   | **xclip** OR **xsel**              | Clipboard management                   |
| **hyprpaper**                     | →   | **feh** OR **nitrogen**            | Wallpaper setter                       |
| **hyprland-autoname-workspaces**  | →   | **i3-workspace-names** (optional)  | Or custom script                       |
| **dunst**                         | ✓   | **dunst**                          | Already works on X11!                  |
| **alacritty**                     | ✓   | **alacritty**                      | Already works on X11!                  |
| **brightnessctl**                 | ✓   | **brightnessctl**                  | Already works on X11!                  |
| **playerctl**                     | ✓   | **playerctl**                      | Already works on X11!                  |

---

## Complete Package List

```bash
# Core i3 + Xorg
yay -S xorg-server xorg-xinit xorg-xrandr arandr
yay -S i3-wm i3status i3lock

# Compositor (for transparency, blur, animations, shadows)
yay -S picom

# Tools that need replacing
yay -S flameshot              # Replace grim + slurp (GUI screenshot tool)
yay -S maim                   # For OCR screenshot script
yay -S xclip                  # Replace wl-copy/wl-paste
yay -S feh                    # Replace hyprpaper
yay -S xdotool                # X11 window manipulation
yay -S tesseract              # OCR engine (if not already installed)

# Optional but recommended
yay -S lxappearance           # GTK theme switcher
yay -S qt5ct qt6ct            # Already have these
yay -S autorandr              # Monitor profile management (optional)
yay -S unclutter              # Hide mouse cursor when idle
yay -S xss-lock               # Screen locker integration

# Tools that already work (no action needed)
# - dunst
# - alacritty
# - brightnessctl
# - playerctl
# - pasystray
# - blueman-applet
# - caja
```

---

## i3 Config Structure Plan

**Location**: `~/.config/i3/config`

### Key Mapping from Hyprland → i3

```
# Modifier
$mainMod (SUPER) → $mod (Mod4)

# Basic Actions
SUPER+Return         → $mod+Return              (terminal)
SUPER+SHIFT+Q        → $mod+Shift+q             (kill window)
SUPER+SHIFT+M        → $mod+Shift+e             (exit i3 - will create menu)
SUPER+E              → $mod+e                   (file manager)
SUPER+V              → $mod+Shift+space         (toggle floating)
SUPER+F              → $mod+f                   (fullscreen)
SUPER+R              → $mod+d                   (dmenu launcher)

# Focus Movement (vim keys - already use these!)
SUPER+h/j/k/l        → $mod+h/j/k/l             (same!)

# Window Movement
SUPER+SHIFT+H/J/K/L  → $mod+Shift+h/j/k/l       (same!)

# Window Resizing
SUPER+ALT+h/j/k/l    → $mod+r (resize mode)     (different approach)

# Workspaces
SUPER+1-9,0          → $mod+1-9,0               (same!)
SUPER+SHIFT+1-9,0    → $mod+Shift+1-9,0         (move to workspace)

# Monitor Movement
SUPER+SHIFT+period   → $mod+Shift+greater       (move workspace right)
SUPER+SHIFT+comma    → $mod+Shift+less          (move workspace left)

# Screenshots
SUPER+SHIFT+S        → $mod+Shift+s             (region screenshot - calls ~/.scripts/x11_screenshot.sh)
SUPER+SHIFT+A        → $mod+Shift+a             (OCR extraction - calls ~/.scripts/x11_extracttext.sh)

# Special
SUPER+CTRL+Q         → $mod+Ctrl+q              (suspend)
SUPER+Tab            → $mod+Tab                 (cycle windows - via dmenu)
```

---

## Picom Config Plan

**Location**: `~/.config/picom/picom.conf`

Based on your Hyprland config (transparency, blur, animations, shadows, 5px rounding, VSync):

```ini
# Backend & Performance
backend = "glx";
vsync = true;
glx-no-stencil = true;
glx-no-rebind-pixmap = true;

# Shadows (you had shadows enabled in Hyprland)
shadow = true;
shadow-radius = 12;
shadow-offset-x = -7;
shadow-offset-y = -7;
shadow-opacity = 0.75;

# Fading/Animations
fading = true;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-delta = 4;

# Transparency (you used opacity 1.0 in Hyprland, but had blur enabled)
inactive-opacity = 1.0;
active-opacity = 1.0;
frame-opacity = 1.0;

# Blur (kawase blur for performance)
blur-method = "dual_kawase";
blur-strength = 5;
blur-background = true;
blur-background-frame = false;
blur-background-fixed = false;

# Rounded corners (5px like Hyprland)
corner-radius = 5;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'"
];

# Window type settings
wintypes:
{
  tooltip = { fade = true; shadow = true; opacity = 0.95; focus = true; full-shadow = false; };
  dock = { shadow = false; clip-shadow-above = true; }
  dnd = { shadow = false; }
  popup_menu = { opacity = 0.95; }
  dropdown_menu = { opacity = 0.95; }
};
```

---

## .xinitrc Plan

**Location**: `~/.xinitrc`

Since you chose startx/xinit, this file will launch your session:

```bash
#!/bin/sh

# Source your profile
[ -f ~/.profile ] && . ~/.profile

# Merge X resources (if you create ~/.Xresources later)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Set keyboard repeat rate (adjust to preference)
xset r rate 300 50

# Disable bell
xset b off

# Monitor setup (adjust for your multi-monitor setup)
# Based on your Hyprland: eDP-1 (laptop), DVI-I-1, DVI-I-2
# You may need to adjust these with xrandr -q first
xrandr --output eDP-1 --mode 1920x1080 --pos 0x0 --rotate normal \
       --output DVI-I-1 --mode 2560x1440 --pos 1920x0 --rotate normal --primary \
       --output DVI-I-2 --mode 1920x1080 --pos 4480x0 --rotate normal &

# Set wallpaper
feh --bg-scale ~/Pictures/wallpaper.jpg &

# Start compositor (picom)
picom &

# Start system tray apps (from your Hyprland autostart)
pasystray &
blueman-applet &
dunst &
owncloud &

# Launch waybar replacement script if you have one
# Or i3status will be handled by i3 config itself

# Screen locker (optional - locks screen on suspend/sleep)
xss-lock -- i3lock -c 000000 &

# Hide mouse cursor after inactivity (optional)
unclutter --timeout 3 &

# Update environment variables for X11
export XDG_CURRENT_DESKTOP=i3
export QT_QPA_PLATFORM=xcb                    # Changed from wayland
export QT_QPA_PLATFORMTHEME=qt6ct             # Keep

# Finally, exec i3
exec i3
```

**Important**: DO NOT modify `~/.profile` - keep it as-is for Hyprland!

The environment variables above (XDG_CURRENT_DESKTOP=i3, QT_QPA_PLATFORM=xcb) are set in .xinitrc and only apply when starting i3. When you launch Hyprland via `~/bin/hypr`, your original ~/.profile settings will be used.

---

## Scripts Strategy

**Approach**: Create new X11 versions of scripts with `x11_` prefix to keep Hyprland scripts intact.

This allows you to:
- Keep Hyprland setup functional if you want to switch back
- Use the same script names but prefixed for X11
- Update i3 keybindings to call the X11 versions

### New Scripts to Create

#### ~/.scripts/x11_screenshot.sh
New X11 version using flameshot:

```bash
#!/bin/sh
# Simple wrapper for flameshot
# Flameshot handles the GUI, region selection, and clipboard automatically
flameshot gui
```

**Note**: Flameshot has built-in features for:
- Region selection (interactive GUI)
- Automatic clipboard copy
- Annotations and editing
- Save to file with custom naming

If you want to maintain the same auto-save behavior as before:

```bash
#!/bin/sh
path=$HOME"/Pictures/screenshots/"
mkdir -p "$path"
timestamp=$(date +"%Y-%m-%d-%H:%M:%S")
active_window=$(xdotool getactivewindow getwindowclassname 2>/dev/null || echo "unknown")
out="${path}/${timestamp}-${active_window}.png"

# Flameshot with auto-save to specific path and clipboard
flameshot gui --path "$path" --filename "${timestamp}-${active_window}"
```

#### ~/.scripts/x11_extracttext.sh
New X11 version using maim + tesseract:

```bash
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
```

---

## Migration Steps Checklist

### Phase 1: Pre-Migration Prep
- [ ] 1. Note your current monitor setup for reference
  ```bash
  hyprctl monitors > ~/monitor-setup.txt
  ```

### Phase 2: Install Packages
- [ ] 2. Install core i3 + Xorg packages
  ```bash
  yay -S xorg-server xorg-xinit xorg-xrandr arandr i3-wm i3status i3lock
  ```

- [ ] 3. Install compositor with features you need
  ```bash
  yay -S picom
  ```

- [ ] 4. Install replacement tools
  ```bash
  yay -S flameshot maim xclip feh xdotool tesseract
  ```

- [ ] 5. Install optional utilities
  ```bash
  yay -S lxappearance autorandr unclutter xss-lock
  ```

### Phase 3: Create Configs
- [ ] 6. Create ~/.xinitrc (see plan above)

- [ ] 7. Create ~/.config/i3/config
  ```bash
  mkdir -p ~/.config/i3
  # (Will provide full config template if you want)
  ```

- [ ] 8. Create ~/.config/picom/picom.conf (see plan above)
  ```bash
  mkdir -p ~/.config/picom
  ```

- [ ] 9. (Optional) Customize dmenu appearance in i3 config or Xresources

- [ ] 10. DO NOT modify ~/.profile (keep it as-is for Hyprland)
  - Environment variables will be set in .xinitrc for i3 only
  - This keeps both Hyprland and i3 working independently

- [ ] 11. Create new X11 scripts in ~/.scripts/
  - Create x11_screenshot.sh (flameshot version)
  - Create x11_extracttext.sh (maim + tesseract version)
  - Keep original screenshot.sh and extracttext.sh for Hyprland
  - Update i3 config to call x11_* versions

### Phase 4: Testing
- [ ] 12. Test monitor setup first
  ```bash
  startx -- :1  # Test on display :1 to keep Hyprland running
  ```

- [ ] 13. Test keybindings, verify everything works

- [ ] 14. Set wallpaper location for feh in .xinitrc

- [ ] 15. Test multi-monitor workspace movement

### Phase 5: Finalize
- [ ] 16. Logout of Hyprland completely

- [ ] 17. From TTY, run: `startx`

- [ ] 18. Test all autostart apps launched correctly

- [ ] 19. (Optional) Add i3 autostart to .zprofile:
  ```bash
  if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec startx
  fi
  ```

- [ ] 20. (Optional) Remove Hyprland packages if satisfied:
  ```bash
  yay -R hyprland hyprland-autoname-workspaces-git \
         xdg-desktop-portal-hyprland
  ```

---

## Additional Considerations

### 1. Monitor Configuration
Your Hyprland config shows 3 monitors. You'll want to:
- Test with `xrandr -q` first to see actual output names (they might differ from Wayland)
- Consider using `arandr` (GUI) to set up monitors, then save the script
- Or use `autorandr` to save profiles for different setups

### 2. i3status Configuration
Create `~/.config/i3status/config` for your status bar. Basic example:

```
general {
    colors = true
    interval = 5
}

order += "wireless _first_"
order += "ethernet _first_"
order += "battery all"
order += "disk /"
order += "load"
order += "memory"
order += "tztime local"

wireless _first_ {
    format_up = "W: %essid %quality"
    format_down = "W: down"
}

ethernet _first_ {
    format_up = "E: %ip"
    format_down = "E: down"
}

battery all {
    format = "%status %percentage %remaining"
}

tztime local {
    format = "%Y-%m-%d %H:%M:%S"
}

load {
    format = "load: %1min"
}

memory {
    format = "mem: %used"
}

disk "/" {
    format = "disk: %avail"
}
```

### 3. Gaps & Visual Appearance
Your Hyprland has 5px gaps. For i3, you'll need `i3-gaps` (which is now merged into mainline i3):

```
# In i3 config
gaps inner 5
gaps outer 5
```

---

## What Will NOT Be Modified (Hyprland Safety)

To ensure both environments work independently:
- ✅ `~/.config/hypr/*` - All Hyprland configs stay untouched
- ✅ `~/.profile` - Keep as-is (used by Hyprland's ~/bin/hypr script)
- ✅ `~/.scripts/screenshot.sh` - Keep original (new x11_screenshot.sh created instead)
- ✅ `~/.scripts/extracttext.sh` - Keep original (new x11_extracttext.sh created instead)
- ✅ All Wayland packages (hyprland, wofi, grim, etc.) - Not removed

## What Will Be Created (New for i3)

- ✅ `~/.xinitrc` - New file for starting i3 with startx
- ✅ `~/.config/i3/config` - New i3 config
- ✅ `~/.config/picom/picom.conf` - New compositor config
- ✅ `~/.config/i3status/config` - New status bar config
- ✅ `~/.scripts/x11_screenshot.sh` - New X11 screenshot script
- ✅ `~/.scripts/x11_extracttext.sh` - New X11 OCR script
- ✅ New X11 packages (i3-wm, picom, flameshot, etc.)

**How to switch between them:**
- Start Hyprland: Run `~/bin/hypr` from TTY (uses your existing setup)
- Start i3: Run `startx` from TTY (uses new .xinitrc)

---

## Summary

You're migrating from a well-configured Hyprland setup. The good news:
- ✅ Most of your tools (dunst, alacritty, brightnessctl, playerctl) work on both
- ✅ Your keybindings are vim-style and will map cleanly to i3
- ✅ Your scripts just need tool replacements (hyprctl→xdotool, grim→maim, wl-copy→xclip)
- ✅ You're on Arch, so all packages are readily available

---

## Next Steps

After reviewing this plan, you can:
1. Generate a complete i3 config file with all your keybindings migrated
2. Create the actual config files (.xinitrc, picom.conf, updated scripts)
3. Begin the migration process following the checklist above
