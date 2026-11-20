.pragma library
// Shell/Lua command builders for the SETTINGS station. Pure functions: LiveData runs the
// results, FakeData only logs them, so what the mock prints is exactly what the real one runs.

const D = '"${XDG_STATE_HOME:-$HOME/.local/state}/lcars"';
const EVAL_OK = 'o=$(hyprctl eval "$L" 2>&1); case $o in *rror*) notify-send -u critical "LCARS" "$o";; esac';
const MONS = 'dofile(os.getenv("HOME").."/.config/hypr/monitors.lua") return ""';
const LCARS = 'dofile(os.getenv("HOME").."/.config/hypr/lcars.lua") return ""';

// keys the overrides file may hold (same whitelist as hypr/lcars.lua)
const LOOK = [
    { key: "general.gaps_in", label: "GAPS INNER", type: "int" },
    { key: "general.gaps_out", label: "GAPS OUTER", type: "int" },
    { key: "general.border_size", label: "BORDER", type: "int" },
    { key: "decoration.rounding", label: "ROUNDING", type: "int" },
    { key: "decoration.blur.enabled", label: "BLUR", type: "bool" },
    { key: "decoration.shadow.enabled", label: "SHADOWS", type: "bool" },
    { key: "animations.enabled", label: "ANIMATIONS", type: "bool" }];
const EXTRA = ["input.kb_layout", "input.repeat_rate", "input.repeat_delay"];

function labelOf(k) { const l = LOOK.find(x => x.key === k); return l ? l.label : k; }
function typeOf(k) { const l = LOOK.find(x => x.key === k); return l ? l.type : ""; }
function clean(k, v) {
    if (typeOf(k) === "bool") return v === "true" || v === true ? "true" : v === "false" || v === false ? "false" : null;
    if (typeOf(k) === "int") {
        const t = typeof v === "number" ? String(v) : typeof v === "string" ? v.trim() : "";
        return /^\d+$/.test(t) ? String(Math.min(40, Number(t))) : null;
    }
    return null;
}

// { "a.b.c": "5" } -> hl.config({ a = { b = { c = 5 } } })
function luaCfg(kv) {
    const root = {};
    for (const k in kv) {
        const v = clean(k, kv[k]);
        if (v === null) continue;
        const p = k.split("."); let n = root;
        for (let i = 0; i < p.length - 1; i++) n = n[p[i]] = n[p[i]] || {};
        n[p[p.length - 1]] = v;
    }
    const ser = o => typeof o === "object" ? "{ " + Object.keys(o).map(k => k + " = " + ser(o[k])).join(", ") + " }" : o;
    return "hl.config(" + ser(root) + ")";
}

// write olds, then overrides (key=value text), append one log line (log trimmed to 200), then eval `lua`
// ("" = nothing). Writes sit under flock so two LCARS writers cannot interleave.
function ovrWrite(ovr, olds, logLine, lua) {
    const kv = m => Object.keys(m).map(k => k + "=" + m[k]).join("\n") + (Object.keys(m).length ? "\n" : "");
    const sh = 'D=' + D + '; mkdir -p "$D"; ( flock 9; ' +
        'printf %s "$2" > "$D/olds.tmp" && mv "$D/olds.tmp" "$D/olds"; ' +
        'printf %s "$1" > "$D/overrides.tmp" && mv "$D/overrides.tmp" "$D/overrides"; ' +
        '[ -n "$3" ] && { printf "%s\\n" "$3" >> "$D/log.jsonl"; tail -n 200 "$D/log.jsonl" > "$D/log.tmp" && mv "$D/log.tmp" "$D/log.jsonl"; }; ' +
        ') 9>"$D/.lock"; ' +
        'L=$4; [ -n "$L" ] && { ' + EVAL_OK + '; }; true';
    return ["sh", "-c", sh, "sh", kv(ovr), kv(olds), logLine, lua];
}
function applyLua() { return LCARS; }
function revertLua(olds, keys) { const kv = {}; for (const k of keys) if (olds[k] !== undefined) kv[k] = olds[k]; return Object.keys(kv).length ? luaCfg(kv) + ' return ""' : ""; }

function stateRead() {
    return ["sh", "-c", 'D=' + D + '; cat "$D/overrides" 2>/dev/null; echo ---; cat "$D/olds" 2>/dev/null; echo ---; tail -n 30 "$D/log.jsonl" 2>/dev/null; true'];
}
function parseKv(t) {
    const m = {};
    for (const l of (t || "").split("\n")) { const r = l.match(/^([\w.]+)=(\S+)$/); if (r) m[r[1]] = r[2]; }
    return m;
}
function parseState(text) {
    const [a, b, c] = text.split(/^---$/m);
    const log = [];
    for (const l of (c || "").split("\n")) { try { if (l.trim()) log.push(JSON.parse(l)); } catch (e) {} }
    return { ovr: parseKv(a), olds: parseKv(b), log: log.reverse() };
}
function optsRead() {
    const keys = LOOK.map(l => l.key).concat(EXTRA).map(k => k.replace(/\./g, ":")).join(" ");
    return ["sh", "-c", 'for k in ' + keys + '; do v=$(hyprctl getoption $k -j 2>/dev/null | jq -r \'(if has("bool") then .bool elif has("int") then .int elif has("css") then .css else .str end)|tostring|split(" ")[0]\'); echo "$k $v"; done'];
}
function parseOpts(text) {
    const m = {};
    for (const l of text.split("\n")) { const r = l.match(/^(\S+) (\S+)$/); if (r && r[2] !== "null") m[r[1].replace(/:/g, ".")] = r[2]; }
    return m;
}
function copyLua(k, v) { return luaCfg({ [k]: v }); }

// ---- display ----
function monRead() {
    return ["sh", "-c", "hyprctl monitors all -j 2>/dev/null | jq -c '[.[]|{name,desc:.description,off:.disabled,mirror:(.mirrorOf!=\"none\"),x,y,tf:.transform,scale,hz:(.refreshRate|round),w:.width,h:.height,modes:.availableModes}]'"];
}
// refresh rates offered for a monitor: modes at the current resolution, externals capped at 120
function rates(m) {
    const pre = m.w + "x" + m.h + "@", out = [];
    for (const s of m.modes || []) {
        if (s.indexOf(pre) !== 0) continue;
        const hz = Math.round(parseFloat(s.slice(pre.length)));
        if (hz > 0 && !out.includes(hz) && (m.name.indexOf("eDP") === 0 || hz <= 120)) out.push(hz);
    }
    return out.sort((a, b) => b - a);
}
// ---- keep-or-revert: a detached dead-man, so it still fires if the shell dies ----
// $D/pending = "<epoch> <kind> <text>". Applying writes it and spawns a `sleep 15` revert that only acts
// if the same pending is still there. KEEP deletes it, REVERT acts now and deletes it. All under the
// layouts lock, so a double fire is a no-op. The QML countdown is display only.
const SETUP = 'S="${XDG_STATE_HOME:-$HOME/.local/state}"; D="$S/lcars"; K="$S/hypr/layouts"; mkdir -p "$D" "$K"; ';
// $1 = monitors.lua eval, $2 = seconds to wait first (0 = now), $3 = pending stamp it must still match ("" = any)
const REVERT = SETUP + 'L=$1; [ "$2" -gt 0 ] && sleep "$2"; ( flock 9; [ -f "$D/pending" ] || exit 0; read -r st kind _ < "$D/pending"; ' +
    '[ -z "$3" ] || [ "$st" = "$3" ] || exit 0; ' +
    'if [ "$kind" = scale ]; then p=$(cat "$D/layout.profile" 2>/dev/null); if [ -n "$p" ]; then ' +
    'if [ "$(cat "$D/layout.had" 2>/dev/null)" = 1 ]; then cp "$D/layout.bak" "$K/$p"; else rm -f "$K/$p"; fi; fi; fi; ' +
    EVAL_OK + '; rm -f "$D/pending" ) 9>"$K/.lock"';
// write pending, spawn the dead-man (setsid: not in the shell's process group)
const ARM = 'T=$(date +%s); printf "%s %s %s\\n" "$T" "$KIND" "$TXT" > "$D/pending"; ' +
    'setsid -f sh -c "$REV" sh "$MONS" 15 "$T" </dev/null >/dev/null 2>&1; ';
function _armEnv() { return 'REV=' + shq(REVERT) + '; MONS=' + shq(MONS) + '; '; }
function shq(t) { return "'" + String(t).replace(/'/g, "'\\''") + "'"; }
const NAME = /^[\w-]+$/;
// snapshot the layout file, arm the dead-man, then the stock script's `scale` (it changes the number and saves)
function scaleApply(name, s) {
    const sh = SETUP + _armEnv() + 'p=$(sed -n "s/^profile //p" "${XDG_RUNTIME_DIR:-/tmp}/hypr-monitors" 2>/dev/null); [ -n "$p" ] || exit 1; ' +
        'rm -f "$D/layout.bak"; echo "$p" > "$D/layout.profile"; ' +
        'if cp "$K/$p" "$D/layout.bak" 2>/dev/null; then echo 1 > "$D/layout.had"; else echo 0 > "$D/layout.had"; fi; ' +
        'KIND=scale; TXT="$1 SCALE $2"; ' + ARM + 'exec "$HOME/.config/hypr/scripts/monitor-layout.sh" scale "$1" "$2"';
    return ["sh", "-c", sh, "sh", name, String(s)];
}
// live refresh change: arm the dead-man, then eval `lua`
function refreshApply(m, hz) {
    const sh = SETUP + _armEnv() + 'L=$3; [ -n "$L" ] || exit 1; KIND=refresh; TXT="$1 $2 HZ"; ' + ARM + EVAL_OK;
    return ["sh", "-c", sh, "sh", m.name, String(hz), refreshLua(m, hz)];
}
// revert now. Kind comes from the pending file, so a stale click after the dead-man fired does nothing.
function displayRevert() { return ["sh", "-c", REVERT, "sh", MONS, "0", ""]; }
// KEEP: drop pending under the lock; a refresh is also saved into the layout
function keepCmd(save) {
    return ["sh", "-c", SETUP + '( flock 9; rm -f "$D/pending" ) 9>"$K/.lock"; ' + (save ? 'exec "$HOME/.config/hypr/scripts/monitor-layout.sh" save' : 'true')];
}
function pendingRead() { return ["sh", "-c", 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/lcars/pending" 2>/dev/null; true']; }
// "epoch kind text" -> { stamp(ms), kind, text } or null
function parsePending(t) {
    const m = String(t || "").trim().match(/^(\d+) (scale|refresh) (.*)$/);
    return m ? { stamp: Number(m[1]) * 1000, kind: m[2], text: m[3] } : null;
}
// scales worth offering: whole logical size (Hyprland rounds otherwise); eDP panels never 3
function scales(m) {
    const ok = v => { const w = m.w / v, h = m.h / v; return Math.abs(w - Math.round(w)) < 0.001 && Math.abs(h - Math.round(h)) < 0.001; };
    return [1, 1.25, 1.5, 1.6, 2, 3].filter(v => (v !== 3 || m.name.indexOf("eDP") !== 0) && ok(v));
}
// live refresh change for one output (same fields monitor-layout.sh's apply() emits)
function refreshLua(m, hz) {
    if (!NAME.test(m.name)) return "";
    return 'hl.monitor({ output = "' + m.name + '", mode = "' + m.w + "x" + m.h + "@" + hz + '", position = "' + m.x + "x" + m.y +
        '", scale = ' + (Math.round(m.scale * 100) / 100) + ", transform = " + m.tf + ', mirror = "none", disabled = false }) return ""';
}
function evalCmd(lua) { return ["sh", "-c", 'L=$1; ' + EVAL_OK, "sh", lua]; }
function saveCmd() { return ["sh", "-c", 'exec "$HOME/.config/hypr/scripts/monitor-layout.sh" save']; }

// ---- overrides state machine ----
// st = { ovr, olds, now }: ovr = key->value in the file, olds = key->value of YOUR config before the
// first override, now = key->value live. Returns the next state plus the argv to run, or null.
function _log(key, old, nw, what, t) { return JSON.stringify({ t: t, key: key, old: old, new: nw, what: what }); }
function ovrChange(st, op, key, value, t, what) {
    const ovr = Object.assign({}, st.ovr), olds = Object.assign({}, st.olds);
    let lines = [], lua = LCARS;
    if (op === "set") {
        const v = clean(key, value);
        if (v === null) return null;
        const prev = ovr[key] !== undefined ? ovr[key] : (st.now[key] !== undefined ? st.now[key] : "");
        if (olds[key] === undefined && st.now[key] !== undefined) olds[key] = st.now[key];
        ovr[key] = v;
        lines.push(_log(key, prev, v, what || "SET", t));
    } else {
        const keys = op === "clearAll" ? Object.keys(ovr) : (ovr[key] !== undefined ? [key] : []);
        if (!keys.length) return null;
        lua = revertLua(olds, keys);
        for (const k of keys) { lines.push(_log(k, ovr[k], olds[k] !== undefined ? olds[k] : "", what || "CLEAR", t)); delete ovr[k]; delete olds[k]; }
    }
    return { ovr: ovr, olds: olds, argv: ovrWrite(ovr, olds, lines.join("\n"), lua) };
}
function undoOp(st, entry) {
    return st.olds[entry.key] !== undefined && st.olds[entry.key] === entry.old
        ? ovrChange(st, "clear", entry.key, "", Date.now(), "UNDO")
        : ovrChange(st, "set", entry.key, entry.old, Date.now(), "UNDO");
}
