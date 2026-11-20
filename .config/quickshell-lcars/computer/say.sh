#!/bin/bash
# say.sh "<text>" [--out file.wav] | --start | --wait | --keep on|off | --stop
# Renders sentence by sentence from Kokoro (raw pcm stream) straight through the ship effect into pw-cat,
# so sound starts after the FIRST sentence is rendered, not the whole text. Starts Kokoro itself if needed.
# stdout status lines for the shell: "loading" (waiting for kokoro), "ready" (about to play). Exit 1 = voice unavailable.
# Killing this script (TERM) stops the whole pipeline including the player (own process group).
# env: COMPUTER_VOICE (kokoro voice or blend, "a(2)+b(1)"), COMPUTER_SPEED, COMPUTER_FX (1/0), COMPUTER_PORT,
#      COMPUTER_THREADS (torch threads for kokoro, default 6), COMPUTER_PLAYER (test hook: command reading s16le 24k mono on stdin)
VOICE=${COMPUTER_VOICE:-af_nova}
SPEED=${COMPUTER_SPEED:-1.0}
FX=${COMPUTER_FX:-1}
PORT=${COMPUTER_PORT:-8891}  # 8880 is taken by another local service (Caddy)
THREADS=${COMPUTER_THREADS:-6}  # measured: all 16 cores oversubscribe on this CPU, 4-6 is 3-5x faster per sentence
URL=http://127.0.0.1:$PORT
K=$HOME/.voicemode/services/kokoro
RT=${XDG_RUNTIME_DIR:-/tmp}/lcars-computer
USED=$RT/kokoro.used  # touched on every line spoken; the watchdog stops kokoro 10 minutes after the last one
CHAIN='highpass=f=150,lowpass=f=5800,equalizer=f=2500:t=q:w=1:g=-2,acompressor=threshold=-22dB:ratio=3:attack=5:release=80,apad=pad_dur=0.3,aecho=0.85:0.75:38|71:0.16|0.08,alimiter=limit=0.9'
mkdir -p "$RT"

up() { curl -sf -m 2 "$URL/health" >/dev/null; }
KPAT="uvicorn api.src.main:app.*--port $PORT"
KP() { pgrep -f "$KPAT" >/dev/null; }  # alive check by command line: no pid file to go stale or be reused

case $1 in
--start)
  touch "$USED"
  # one watchdog per machine; it ends by itself when kokoro is gone. Covers a crashed shell, mute, the dev window and idle RAM (1.5 GB).
  # ponytail: fixed 10 min, make it a CONFIG value if the reload wait annoys
  pgrep -f "say\.sh --watch$" >/dev/null || SAY_SID=1 setsid nohup "$0" --watch >/dev/null 2>&1 &
  up && exit 0
  KP && exit 0  # still loading
  cd "$K" || exit 1
  # same env as start-cpu.sh, minus its network install step; own port; own process group so a say interrupt (kill 0) never reaches it
  OMP_NUM_THREADS=$THREADS MKL_NUM_THREADS=$THREADS USE_GPU=false USE_ONNX=false PYTHONPATH=$K:$K/api MODEL_DIR=src/models VOICES_DIR=src/voices/v1_0 \
    setsid nohup .venv/bin/python -B -m uvicorn api.src.main:app --host 127.0.0.1 --port "$PORT" >"$RT/kokoro.log" 2>&1 &
  exit 0 ;;  # ready in ~15 s; say waits on /health itself
--wait)  # warm-up for the shell: start kokoro (idempotent), print "loading" while it comes up, exit when it answers (or after 45 s)
  "$0" --start
  up && exit 0
  echo loading
  for _ in $(seq 90); do up && exit 0; KP || exit 1; sleep 0.5; done
  exit 1 ;;
--keep)  # KEEP VOICE LOADED: while this flag file exists the watchdog never unloads kokoro for being idle
  [ "$2" = on ] && touch "$RT/kokoro.keep" || rm -f "$RT/kokoro.keep"
  exit 0 ;;
--stop)
  pkill -f "$KPAT"; exit 0 ;;
--watch)
  while sleep "${COMPUTER_TICK:-60}"; do
    KP || exit 0
    [ -e "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lcars-on" ] || { pkill -f "$KPAT"; exit 0; }   # LCARS is off: unload even with KEEP VOICE LOADED
    [ -e "$RT/kokoro.keep" ] && continue
    [ $(( $(date +%s) - $(stat -c %Y "$USED" 2>/dev/null || echo 0) )) -gt "${COMPUTER_IDLE:-600}" ] && pkill -f "$KPAT"
  done ;;
esac

OUT=
TEXT=
while [ $# -gt 0 ]; do
  case $1 in --out) OUT=$2; shift 2 ;; *) TEXT=$1; shift ;; esac
done
[ -n "$TEXT" ] || { echo "say.sh: no text" >&2; exit 2; }

# own process group so one kill 0 reaches curl, ffmpeg and the player (the caller only knows our pid)
if [ -z "$SAY_SID" ] && [ "$(ps -o pgid= $$ | tr -d ' ')" != $$ ]; then
  SAY_SID=1 exec setsid "$0" ${OUT:+--out "$OUT"} "$TEXT"
fi
set -o pipefail
trap 'trap "" TERM INT; kill 0; exit 143' TERM INT

if ! up; then
  echo loading
  "$0" --start
  for _ in $(seq 90); do  # 45 s cap
    up && break
    KP || { echo "say.sh: kokoro died while loading, see $RT/kokoro.log" >&2; exit 1; }
    sleep 0.5 & wait $!
  done
  up || { echo "say.sh: kokoro not ready after 45 s" >&2; "$0" --stop; exit 1; }  # stop it so the next line starts clean
fi
touch "$USED"
echo ready

if [ "$FX" = 1 ]; then AF=$CHAIN; else AF=anull; fi
if [ -n "$OUT" ]; then SINK=(ffmpeg -v error -y -f s16le -ar 24000 -ac 1 -i - -af "$AF" "$OUT")
else
  SINK=(ffmpeg -v error -nostdin -fflags nobuffer -probesize 32 -analyzeduration 0 -f s16le -ar 24000 -ac 1 -i - -af "$AF" -flush_packets 1 -f s16le -ar 24000 -ac 1 -)
fi
PLAY=(timeout --foreground 120 pw-cat -p --raw --rate 24000 --channels 1 --format s16 -)
[ -n "$COMPUTER_PLAYER" ] && PLAY=(sh -c "$COMPUTER_PLAYER")

render() {  # one pcm request per sentence, concatenated on stdout
  printf '%s\n' "$TEXT" | sed 's/\([.!?]\) \+/\1\n/g' | while IFS= read -r S; do
    [ -n "${S// /}" ] || continue
    jq -n --arg t "$S" --arg v "$VOICE" --argjson s "$SPEED" \
      '{model:"kokoro",input:$t,voice:$v,speed:$s,response_format:"pcm",stream:true}' |
      curl -sfN -m 60 "$URL/v1/audio/speech" -H 'Content-Type: application/json' -d @- || exit 1
  done
}

if [ -n "$OUT" ]; then { render | "${SINK[@]}"; } & else { render | "${SINK[@]}" | "${PLAY[@]}"; } & fi
wait $!
