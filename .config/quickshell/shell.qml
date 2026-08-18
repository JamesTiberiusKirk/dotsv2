//@ pragma UseQApplication
import Quickshell
import "bar"
import "notifs"
import "launcher"
import "osd"

// dshell — quickshell replacement for waybar + dunst + wofi.
// Piloted via `hyprx --shell` (HYPR_SHELL=quickshell); see base.lua autostart.
ShellRoot {
    Frame {}
    Bar {}
    NotifPopups {}
    NotifCenter {}
    Launcher {}
    Osd {}
}
