# deathstar — migration to the quickshell setup

Last pulled before hyprglass/quickshell landed. Repo side is done
(`hosts/deathstar` links `.config/quickshell` + `.scripts/qsmenu`).
Steps on the machine, in order:

1. `git pull` in `~/.dots`, then run `dots-link` to pick up the new symlinks.
2. Update the hyprnux Hyprland fork **first** — the config now uses
   `hl.layer_rule`, spring curves, and the Lua dispatch API; an old build
   chokes on `base.lua`.
3. `hyprpm add https://github.com/hyprnux/hyprglass` + `hyprpm enable hyprglass`
   — after the Hyprland update (hyprpm pins against the running version).
   Startup ordering is handled by `.config/hypr/scripts/load-plugins.sh`.
4. Install packages if missing: `quickshell`, `hyprpaper`
   (wallpaper cycling drives hyprpaper via `.scripts/menu/common/next-wallpaper.sh`).
5. Launch with `hyprx --shell` — sets `HYPR_SHELL=quickshell`.
   Rollback: launch without the flag → waybar/dunst stack.

## Known risks

- nvidia + hyprglass layer blur untested on this box. Worst case
  `hyprpm disable hyprglass`; `plugins.lua` guards on the plugin missing.
- 4 monitors: bar/frame spawn per screen, but the notif center window
  doesn't pin a screen — opens on the default monitor regardless of which
  bell was clicked. Cosmetic, fix later.
