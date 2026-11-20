#!/usr/bin/env bash
# One-off: move project folders under ~/src (gtmux workspaces) on this machine,
# carrying Claude Code history along. Run from anywhere after `git pull` in ~/.dots:
#   bash ~/.dots/.scripts/migrate-to-src.sh
# Kills every Claude first (transcripts are kept; resume with `claude --continue`
# in the new folder). Shows a dry run and asks before moving anything.
set -euo pipefail
cd ~

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "killing every Claude (CLI, background sessions, daemon, chrome host)"
pkill -x claude 2>/dev/null || true
pkill -f '/claude/versions/' 2>/dev/null || true
sleep 1
if pgrep -fl claude; then
	echo "still running (above): close them, then re-run"
	exit 1
fi
echo "none left"

say "dry run"
python3 ~/.dots/.scripts/move-to-src.py

printf '\nMove for real? [y/N] '
read -r ok
[[ $ok == y || $ok == Y ]] || { echo "nothing changed"; exit 0; }

say "moving"
python3 ~/.dots/.scripts/move-to-src.py --run --allow-busy

say "gtmux: update + reload config"
if [[ -d ~/src/ff/gtmux ]] && command -v go >/dev/null; then
	git -C ~/src/ff/gtmux pull --ff-only
	(cd ~/src/ff/gtmux && go install ./cmd/gtmux)
	gtmux upgrade || echo "gtmux not running: start it with gtmux attach"
else
	echo "skipped: no ~/src/ff/gtmux or no go; install gtmux, then: gtmux upgrade"
fi

say "done"
echo "resume a project's Claude:  cd ~/src/<ws>/<project> && claude --continue"
echo "undo log + backups:         ls ~/move-undo-*.json ~/.claude.json.premove-*"
