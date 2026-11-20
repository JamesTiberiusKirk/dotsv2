#!/bin/bash
# listen.sh                record default mic until ~1.2 s silence after speech (about 40 s cap), print transcript
# listen.sh --file w       transcribe w only
# listen.sh --live         same, but line events on stdout: "level 0-100", "partial <text>", "final <text>"
# listen.sh --live --file w  simulate a recording by feeding w in real time (testing)
# SIGTERM/SIGINT: stop recording, still transcribe (live: still emits final).
W=$HOME/.voicemode/services/whisper
RT=${XDG_RUNTIME_DIR:-/tmp}/lcars-computer
mkdir -p "$RT"
find "$RT" -maxdepth 1 -name "listen.*" -mmin +2 -exec rm -rf {} + 2>/dev/null   # leftovers of a hard-killed run (microphone audio)
TMP=$(mktemp -d "$RT/listen.XXXXXX")
trap 'kill $PID $PJ 2>/dev/null; rm -rf "$TMP"' EXIT

LIVE=0 FILE=
while [ $# -gt 0 ]; do case $1 in --live) LIVE=1;; --file) FILE=$2; shift;; esac; shift; done

# transcript of wav $1, extra whisper args after; one clean line
tx() { local f=$1; shift
  "$W/build/bin/whisper-cli" -m "$W/models/ggml-base.bin" -l en -nt -np -sns "$@" -f "$f" 2>/dev/null |
    tr '\n' ' ' | sed 's/^ *//; s/ *$//; s/  */ /g'; }

if [ $LIVE = 0 ] && [ -n "$FILE" ]; then WAV=$FILE; else
  WAV=$TMP/in.wav
  STOP=0; trap 'STOP=1' TERM INT
  # start chirp first (COMPUTER_CHIRP=wav path) so the mic does not record it; a cut-short tap during it still exits cleanly
  if [ -n "$COMPUTER_CHIRP" ] && [ -z "$FILE" ]; then pw-play "$COMPUTER_CHIRP" 2>/dev/null & wait $!; fi
  if [ -n "$FILE" ]; then
    # test feeder: writes the wav into in.raw at real-time speed, then zeros (silence) forever
    ffmpeg -v error -y -i "$FILE" -f s16le -ar 16000 -ac 1 "$TMP/src.raw"
    ( T0=$EPOCHREALTIME; SL=$(stat -c %s "$TMP/src.raw"); N=0
      while :; do
        WANT=$(awk -v a="$T0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%d", int((b-a)*16000)*2}')
        if [ $WANT -gt $N ]; then
          if [ $N -lt $SL ]; then tail -c +$((N + 1)) "$TMP/src.raw" | head -c $((WANT - N)) >> "$TMP/in.raw"
          else head -c $((WANT - N)) /dev/zero >> "$TMP/in.raw"; fi
          N=$WANT
        fi
        sleep 0.05
      done ) &
  else
    timeout 45 pw-record --raw --rate 16000 --channels 1 --format s16 "$TMP/in.raw" 2>/dev/null &   # timeout: the mic can never stay open if this script is killed hard
  fi
  PID=$!
  # poll every 0.2 s: loud = peak of the newest 0.2 s above -38 dB
  # (ponytail: fixed threshold, make it relative to a noise floor if a noisy room needs it)
  NEXT=$(awk -v t="$EPOCHREALTIME" 'BEGIN{printf "%.3f", t+0.2}')
  POS=0 SPOKE=0 QUIET=0 TICKS=0 PJ= LASTLOUD=0 SNAP=0 PT=0 LASTP=
  while [ $STOP = 0 ] && [ $TICKS -lt 150 ] && kill -0 $PID 2>/dev/null; do
    if [ $LIVE = 1 ]; then   # live: fixed 0.2 s cadence (ffmpeg time included) so the meter runs ~5/s
      sleep "$(awk -v n="$NEXT" -v t="$EPOCHREALTIME" 'BEGIN{d=n-t; printf "%.3f", (d>0.01?d:0.01)}')" & wait $!
      NEXT=$(awk -v n="$NEXT" 'BEGIN{printf "%.3f", n+0.2}')
    else sleep 0.2 & wait $!; fi
    TICKS=$((TICKS + 1))
    SIZE=$(stat -c %s "$TMP/in.raw" 2>/dev/null || echo 0)
    [ $((SIZE - POS)) -ge $((LIVE * 3200 + (1 - LIVE) * 6400)) ] || continue
    PEAK=$(tail -c +$((POS + 1)) "$TMP/in.raw" | head -c $((SIZE - POS)) |
      ffmpeg -v info -f s16le -ar 16000 -ac 1 -i - -af volumedetect -f null - 2>&1 |
      sed -n 's/.*mean_volume: \(-\?[0-9.]*\) dB.*/\1/p')
    POS=$SIZE
    # PEAK is the chunk's MEAN level: peaks (key clicks, bumps) sat above any fixed threshold on the real mic.
    # FLOOR = quietest chunk so far (clamped), speech = 12 dB above it (ponytail: floor only ever drops; track a moving floor if rooms that get louder matter). Meter: floor -> 0, floor+35 dB -> 100.
    FLOOR=$(awk -v p="${PEAK:--90}" -v f="${FLOOR:--45}" 'BEGIN{if(p<f)f=p; if(f<-55)f=-55; print f}')
    [ $LIVE = 1 ] && awk -v p="${PEAK:--90}" -v f="$FLOOR" 'BEGIN{v=int((p-f)*100/35); if(v<0)v=0; if(v>100)v=100; print "level", v; fflush()}'
    if [ $TICKS -gt 2 ]; then   # first 0.4 s: tail of our own chirp, never counts as speech
      if [ -n "$PEAK" ] && [ "$(echo "$PEAK > $FLOOR + 12" | bc)" = 1 ]; then SPOKE=1 QUIET=0 LASTLOUD=$SIZE
      elif [ $SPOKE = 1 ]; then QUIET=$((QUIET + 1)); [ $QUIET -ge 6 ] && break; fi
    fi
    if [ $LIVE = 1 ]; then
      # collect a finished partial job
      if [ -n "$PJ" ] && ! kill -0 $PJ 2>/dev/null; then
        wait $PJ 2>/dev/null; PJ=
        P=$(cat "$TMP/p.txt" 2>/dev/null)
        [ -n "$P" ] && [ "$P" != "$LASTP" ] && { LASTP=$P; echo "partial $P"; }
      fi
      # new speech >= 0.3 s since last snapshot, >= 1 s since last launch, none running: snapshot + rough pass
      NOW=$TICKS
      if [ -z "$PJ" ] && [ $SPOKE = 1 ] && [ $((LASTLOUD - SNAP)) -ge 9600 ] && [ $((NOW - PT)) -ge 5 ]; then
        SNAP=$SIZE PT=$NOW
        head -c $SIZE "$TMP/in.raw" > "$TMP/snap.raw"
        # ponytail: whole-audio rerun per partial, cost grows with length; fine for ~40 s cap
        ( ffmpeg -v error -y -f s16le -ar 16000 -ac 1 -i "$TMP/snap.raw" "$TMP/snap.wav" &&
          exec nice -n 19 "$W/build/bin/whisper-cli" -m "$W/models/ggml-base.bin" -l en -nt -np -sns \
            -t 8 -bs 1 -bo 1 -nf -f "$TMP/snap.wav" 2>/dev/null | tr '\n' ' ' | sed 's/^ *//; s/ *$//; s/  */ /g' > "$TMP/p.txt" ) &
        PJ=$!
      fi
    fi
  done
  kill $PID 2>/dev/null; wait $PID 2>/dev/null
  if [ -n "$PJ" ]; then pkill -P $PJ 2>/dev/null; kill $PJ 2>/dev/null; wait $PJ 2>/dev/null; PJ=; fi
  if [ ! -s "$TMP/in.raw" ] || [ $SPOKE != 1 ]; then
    [ $LIVE = 1 ] && echo "final "
    exit 0   # never spoke: print nothing
  fi
  ffmpeg -v error -y -f s16le -ar 16000 -ac 1 -i "$TMP/in.raw" "$WAV"
fi

if [ $LIVE = 1 ]; then echo "final $(tx "$WAV" -t 8)"; else tx "$WAV"; echo; fi
