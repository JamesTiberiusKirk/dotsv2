#!/usr/bin/env python3
"""Helper the brain runs (never the model): session files and the read-folder list. Stdlib only.
  host.py sessions <folder>          one JSON line per session, newest first (cap 30): {id, mtime, title}
  host.py transcript <folder> <id>   one JSON line per chat row: {kind, text, title}; exit 3 = no such session
  host.py rm <folder> <id>           delete <id>.jsonl and the <id>/ folder, nothing else
  host.py folders <file> <json list of forbidden prefixes>   lines "ok <~/rel>" or "bad <line> <reason>"
  host.py servers                    the user's own MCP servers from ~/.claude.json: one JSON line {name, type, note}. Names only, NEVER env, headers or urls.
  host.py mcpconfig                  writes $COMPUTER_MCP_FILE (a mcp-<n>-<n>.json in $XDG_RUNTIME_DIR/lcars-computer, default mcp.json, 0600): our server + the servers named in $COMPUTER_SERVERS (space separated)
  host.py attach screen <output> | clipboard   saves an image into ~/computer/attachments (long edge <= 1568), prints "ok <path>" or "err <WORDS>"
  host.py attachments                prints "<count> <bytes>" of ~/computer/attachments
  host.py prune-attachments          deletes attachments older than 24 h
  host.py clear-attachments          deletes the files in ~/computer/attachments (no folders, no links followed)
  host.py watch <json>               follow-up poll. In: [{"sid", "marker" (transcript byte offset at send time), "prompt" (true = also capture the screen if blocked), "sent" (our text: a reply only counts after it arrived)}].
                                     Out: one JSON list [{sid, marker, state finished|blocked|working|gone|unknown, size, name, text, prompt}]. Reads only.
"""
import json, os, re, shutil, subprocess, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import img

HOME = os.path.realpath(os.path.expanduser("~"))
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def sdir(folder):
    p = os.path.realpath(os.path.expanduser(folder))
    if not (p == HOME or p.startswith(HOME + "/")):
        sys.exit(2)
    return os.path.join(HOME, ".claude", "projects", re.sub(r"[/.]", "-", p))


def lines(path, tail=0):
    """Parsed JSON lines of a transcript. tail > 0: only the last <tail> bytes (the first, cut line is dropped): big transcripts stay cheap."""
    with open(path, errors="replace") as f:
        if tail and os.fstat(f.fileno()).st_size > tail:
            f.seek(os.fstat(f.fileno()).st_size - tail)
            f.readline()
        for l in f:
            try:
                j = json.loads(l)
            except ValueError:
                continue
            if isinstance(j, dict):
                yield j


FOLLOWUP = "[AUTOMATIC FOLLOW-UP"   # starts every report turn the brain sends (ComputerBrain.qml reportPrompt)


def real_user_text(j):
    """A line the user typed: string content, not meta, not a side chain, not an injected <tag> block."""
    c = (j.get("message") or {}).get("content")
    if j.get("type") == "user" and isinstance(c, str) and not j.get("isMeta") and not j.get("isSidechain") and not c.lstrip().startswith("<"):
        return c
    return None


def tool_text(n, inp):   # same format as ComputerBrain.qml toolText()
    out = [re.sub(r"_+", " ", re.sub(r"^mcp__", "", re.sub(r"^mcp__computer__", "", n))).upper()]
    for k, v in (inp or {}).items():
        v = v if isinstance(v, str) else json.dumps(v, separators=(",", ":"))
        v = re.sub(r"\s+", " ", v)
        out.append("%s: %s" % (k, v[:160] + " ..." if len(v) > 160 else v))
    return "\n".join(out)


ATTACHED = re.compile(r"\n?\[Attached image: (/[^\n\]]+?\.(?:png|jpg|jpeg|gif|webp))\. Look at it with the Read tool\.\]$")
IMG_TOOLS = ("mcp__computer__show_image", "mcp__computer__show_web_image")


def image_row(kind, path, caption):
    """A chat row for an image. A file that is gone stays a row (the shell shows IMAGE MISSING); one the rules no longer allow becomes a note."""
    if not re.fullmatch(r"/[^\x00\n]+", path or ""):
        return {"kind": "note", "text": "IMAGE MISSING", "title": ""}
    cfg = img.cfg_from(os.environ.get("COMPUTER_IMG_CFG"))
    try:
        if os.path.exists(path):
            img.check_local(path, cfg)
        elif img.allowed_path(path, cfg) is None:
            raise img.Refused("no")
    except img.Refused:
        return {"kind": "note", "text": "IMAGE NOT SHOWN", "title": ""}
    return {"kind": kind, "text": re.sub(r"\s+", " ", caption or "")[:120], "title": path}


def result_text(b):
    c = b.get("content")
    return " ".join(x.get("text", "") for x in c if isinstance(x, dict)) if isinstance(c, list) else str(c or "")


def rows(path, tail=0):
    shown = {}      # tool_use id -> caption, for our two image tools
    saved = set()   # tool_use ids of save_note: the answer "ok <path>" becomes a SAVED row
    for j in lines(path, tail):
        t, m = j.get("type"), j.get("message") or {}
        u = real_user_text(j)
        if u is not None:
            m = ATTACHED.search(u)
            if u.startswith(FOLLOWUP):   # a report turn's message: the other session's raw text stays out of the chat
                yield {"kind": "report", "text": "FOLLOW-UP REPORT", "title": ""}
                continue
            yield {"kind": "user", "text": u[:m.start()] if m else u, "title": ""}
            if m:
                yield image_row("attach", m.group(1), "")
        elif t == "assistant" and isinstance(m.get("content"), list):
            if j.get("isSidechain"):
                continue
            for b in m["content"]:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and str(b.get("text", "")).strip():
                    yield {"kind": "text", "text": b["text"].strip(), "title": ""}
                elif b.get("type") == "tool_use":
                    n, inp = str(b.get("name", "")), b.get("input") or {}
                    if n in IMG_TOOLS:
                        shown[b.get("id")] = str(inp.get("caption", ""))
                    elif n == "mcp__computer__save_note":
                        saved.add(b.get("id"))
                    elif n == "mcp__computer__speak":
                        if str(inp.get("text", "")).strip():
                            yield {"kind": "spoken", "text": str(inp["text"]).strip(), "title": ""}
                    elif n == "mcp__computer__show":
                        c = inp.get("content")
                        yield {"kind": "panel", "text": c if isinstance(c, str) else json.dumps(c), "title": str(inp.get("title", ""))}
                    else:
                        yield {"kind": "tool", "text": tool_text(n, inp), "title": ""}
        elif t == "user" and isinstance(m.get("content"), list):
            for b in m["content"]:
                if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                    continue
                if b.get("is_error"):
                    yield {"kind": "error", "text": "TOOL ERROR: " + result_text(b)[:160], "title": ""}
                elif b.get("tool_use_id") in saved:
                    mm = re.match(r"ok (/[^\n]+)", result_text(b))
                    if mm:
                        yield {"kind": "saved", "text": mm.group(1), "title": ""}
                elif b.get("tool_use_id") in shown:
                    mm = re.match(r"ok (/[^\n]+)", result_text(b))
                    if mm:
                        yield image_row("image", mm.group(1), shown[b.get("tool_use_id")])


def cmd_sessions(folder):
    d = sdir(folder)
    fs = []
    for n in os.listdir(d) if os.path.isdir(d) else []:
        if n.endswith(".jsonl") and UUID.fullmatch(n[:-6]):
            try:
                fs.append((os.stat(os.path.join(d, n)).st_mtime, n[:-6]))
            except OSError:
                pass   # removed while listing
    for mt, sid in sorted(fs, reverse=True)[:30]:
        title = ""
        for j in lines(os.path.join(d, sid + ".jsonl")):
            u = real_user_text(j)
            if u is not None and not u.startswith(FOLLOWUP):
                title = re.sub(r"\s+", " ", u).strip()[:80]
                break
        print(json.dumps({"id": sid, "mtime": int(mt), "title": title}))


def cmd_transcript(folder, sid):
    p = os.path.join(sdir(folder), sid + ".jsonl")
    if not UUID.fullmatch(sid) or not os.path.isfile(p):
        sys.exit(3)
    for r in list(rows(p))[-200:]:
        print(json.dumps(r))


def cmd_rm(folder, sid):
    if not UUID.fullmatch(sid):
        sys.exit(2)
    d = sdir(folder)
    p = os.path.join(d, sid + ".jsonl")
    if os.path.isfile(p):
        os.remove(p)
    if os.path.isdir(os.path.join(d, sid)) and not os.path.islink(os.path.join(d, sid)):
        shutil.rmtree(os.path.join(d, sid))


def inside(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")


def cmd_folders(file, forbidden):
    """One folder per line, # comments. Must exist, be under $HOME (not $HOME itself), be a plain path, not sit in a forbidden prefix."""
    bad_prefix = [os.path.realpath(os.path.expanduser(x)) for x in json.loads(forbidden)]
    if not os.path.exists(file):   # first run: start from the template so the shell can watch the file
        os.makedirs(os.path.dirname(file), exist_ok=True)
        shutil.copyfile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "folders-template.txt"), file)
    try:
        text = open(file, errors="replace").read()
    except OSError:
        return
    seen = set()
    for n, l in enumerate(text.splitlines(), 1):
        l = l.strip()
        if not l or l.startswith("#"):
            continue
        if re.search(r"[*?\[\]{}()!\"'`$\\|;&<>]", l):
            print("bad %d odd characters" % n); continue
        p = os.path.realpath(os.path.expanduser(l))
        if not os.path.isdir(p):
            print("bad %d not a folder" % n)
        elif not inside(p, HOME) or p == HOME:
            print("bad %d must be inside your home folder, not the folder itself" % n)
        elif any(inside(p, b) for b in bad_prefix):
            print("bad %d private or protected folder" % n)
        elif p not in seen:
            seen.add(p)
            print("ok ~/" + os.path.relpath(p, HOME))


# ---------------------------------------------------------------- the user's own MCP servers
def claude_json():
    try:
        with open(os.environ.get("LCARS_CLAUDE_JSON") or os.path.join(HOME, ".claude.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def own_servers():
    """{name: config} from user scope plus this computer's own project entry. Unusable names (and `computer`, which is ours) are dropped."""
    j = claude_json()
    out = {}
    for src in ((j.get("projects") or {}).get(os.path.join(HOME, "computer"), {}).get("mcpServers"), j.get("mcpServers")):
        for n, c in (src or {}).items():
            if isinstance(c, dict) and re.fullmatch(r"[A-Za-z0-9_-]{1,40}", str(n)) and "__" not in str(n) and n != "computer":
                out[n] = c
    return out


def cmd_servers():
    for n, c in sorted(own_servers().items()):
        t = str(c.get("type") or "stdio")
        t = t if t in ("stdio", "http", "sse") else "other"
        hay = " ".join([n, str(c.get("command", ""))] + [str(a) for a in c.get("args", []) if isinstance(c.get("args"), list)]).lower()   # looked at, never printed
        note = []
        if t in ("http", "sse"):
            note.append("MAY NEED SIGN-IN")
        if re.search(r"playwright|puppeteer|chrom|browser", hay):
            note.append("OPENS A BROWSER WINDOW")
        print(json.dumps({"name": n, "type": t, "note": ", ".join(note)}))


def cmd_mcpconfig():
    """Our server plus the enabled own servers, copied as they are (they hold env and headers: file 0600 in a 0700 folder under the runtime dir, never in ~/computer)."""
    rt = os.environ.get("XDG_RUNTIME_DIR", "")
    if not rt or not os.path.isdir(rt):
        sys.exit(2)
    d = os.path.join(rt, "lcars-computer")
    out = os.environ.get("COMPUTER_MCP_FILE") or os.path.join(d, "mcp.json")   # one file per run (the brain names it); anywhere else is refused
    if os.path.dirname(out) != d or not re.fullmatch(r"mcp(-[0-9]+-[0-9]+)?\.json", os.path.basename(out)):
        sys.exit(2)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    for n in os.listdir(d):   # a shell crash or reload mid-run leaves its file behind (it holds the servers' env): old ones go
        f = os.path.join(d, n)
        if re.fullmatch(r"mcp-[0-9]+-[0-9]+\.json", n) and f != out and time.time() - os.lstat(f).st_mtime > 3600:
            os.remove(f)
    cfg = {"computer": {"command": "python3", "args": ["-B", os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp.py")],
                        "env": {"COMPUTER_IMG_CFG": os.environ.get("COMPUTER_IMG_CFG", ""), "COMPUTER_NOTES_ONLY": os.environ.get("COMPUTER_NOTES_ONLY", "")}}}
    have = own_servers()
    for n in os.environ.get("COMPUTER_SERVERS", "").split():
        if n in have:
            cfg[n] = have[n]
    tmp = out + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump({"mcpServers": cfg}, f)
    os.replace(tmp, out)


# ---------------------------------------------------------------- attachments (only ever started by a tap, never by the model)
LONG_EDGE = "1568x1568>"


def run(argv, secs=20):
    return subprocess.run(argv, capture_output=True, timeout=secs)


def cmd_attach(how, arg=""):
    os.makedirs(img.ATTACH, mode=0o700, exist_ok=True)
    stamp = int(time.time() * 1000)
    raw = os.path.join(img.ATTACH, ".raw-%d" % stamp)
    try:
        if how == "screen":
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.:-]{0,30}", arg):
                print("err BAD SCREEN NAME"); return
            r = run(["grim", "-o", arg, raw])
        elif how == "clipboard":
            r = run(["wl-paste", "--no-newline", "--type", "image/png"])
            if r.returncode == 0:
                with open(raw, "wb") as f:
                    f.write(r.stdout)
        else:
            sys.exit(64)
        if r.returncode != 0 or not os.path.exists(raw) or os.path.getsize(raw) == 0:
            print("err " + ("NO IMAGE IN CLIPBOARD" if how == "clipboard" else "SCREENSHOT FAILED")); return
        with open(raw, "rb") as f:
            data = f.read(30_000_000)
        try:
            img.vet(data)   # same size rules as every other image
        except img.Refused:
            print("err NOT AN IMAGE"); return
        out = os.path.join(img.ATTACH, "%s-%d.png" % ("shot" if how == "screen" else "clip", stamp))
        r = run(["magick", raw, "-auto-orient", "-resize", LONG_EDGE, "-strip", "PNG:" + out], 40)   # every attachment ends up a bounded png
        if r.returncode != 0 or not os.path.exists(out):
            print("err COULD NOT PREPARE THE IMAGE"); return
        os.chmod(out, 0o600)
        print("ok " + out)
    except (OSError, subprocess.SubprocessError):
        print("err ATTACH FAILED")
    finally:
        try:
            os.remove(raw)
        except OSError:
            pass


def attach_files():
    try:
        return [e for e in os.scandir(img.ATTACH) if e.is_file(follow_symlinks=False) or e.is_symlink()]
    except OSError:
        return []


def cmd_attachments():
    fs = [e for e in attach_files() if not e.name.startswith(".raw-")]
    print(len(fs), sum(e.stat(follow_symlinks=False).st_size for e in fs))


def cmd_prune_attachments():
    """Screenshots and downloaded pictures older than 24 h go: the computer can read ~/computer, so they must not pile up."""
    for e in attach_files():
        try:
            if time.time() - e.stat(follow_symlinks=False).st_mtime > 86400:
                os.remove(e.path)
        except OSError:
            pass


def cmd_clear_attachments():
    for e in attach_files():
        try:
            os.remove(e.path)
        except OSError:
            pass


# ---------------------------------------------------------------- follow-up watch (the brain runs this every 5 s while a told session is watched; reads only)
FAKE = ""   # tests set host.FAKE themselves: <dir>/roll.json replaces `claude agents --json` (rows may carry "screen"), <dir>/projects replaces ~/.claude/projects
REPLY_MAX, SCREEN_MAX = 6000, 3000


def norm(t):
    return " ".join(str(t).split())


def delivered(j, sent):
    """Is this transcript line OUR message arriving: a plain user message, or (told while it was busy) the queued_command attachment where it read the queued text."""
    m = j.get("message") if isinstance(j.get("message"), dict) else {}
    if j.get("type") == "attachment" and isinstance(j.get("attachment"), dict) and j["attachment"].get("type") == "queued_command":
        u = j["attachment"].get("prompt")
    elif j.get("type") == "user" and not j.get("isMeta") and not j.get("isSidechain"):
        u = m.get("content")
        if isinstance(u, list):
            u = " ".join(b.get("text", "") for b in u if isinstance(b, dict) and b.get("type") == "text")
    else:
        return False
    return isinstance(u, str) and norm(u).startswith(sent)


def reply_since(sid, marker, sent=""):
    """(transcript size, an assistant message exists after OUR message, its text with the tail kept). Our message = the first user line after byte offset <marker> that starts with <sent>
    (a message queued behind other work arrives later: the earlier work's answers do not count). sent "" = no such condition. Everything here is another session's words: data only."""
    import mcp
    f = mcp.transcript(sid)
    if not f:
        return 0, False, ""
    try:
        size = os.path.getsize(f)
        start = max(marker if 0 <= marker <= size else 0, size - 4_000_000)   # a marker past the end (file rewritten) reads from the start, within the cap
        with open(f, "rb") as fh:
            fh.seek(start)
            data = fh.read(size - start)
    except OSError:
        return 0, False, ""
    sent = norm(sent)
    got = sent == "" or start > marker   # the window starts after our message: it is already behind us
    seen, texts = False, []
    for l in data.decode("utf-8", "replace").splitlines():   # the first line may be cut in half: it fails to parse and is skipped
        try:
            j = json.loads(l)
        except (ValueError, RecursionError):
            continue
        if not isinstance(j, dict):
            continue
        if not got:
            got = delivered(j, sent)
            continue
        m = j.get("message")
        if not isinstance(m, dict) or j.get("type") != "assistant" or j.get("isSidechain"):
            continue
        seen = True
        for b in m.get("content") if isinstance(m.get("content"), list) else []:
            if isinstance(b, dict) and b.get("type") == "text" and str(b.get("text", "")).strip():
                texts.append(str(b["text"]).strip())
    return size, seen, mcp.clean("\n\n".join(texts))[-REPLY_MAX:]


def blocked_screen(r, rows):
    """What a blocked session asks: its prompt block, else the bottom of its screen. Same capture and parser claude_approve uses."""
    import mcp
    if FAKE:
        return mcp.clean(str(r.get("screen", "")))[-SCREEN_MAX:]
    try:
        lines = mcp.screen_of(*mcp.pane_of(r, rows))
    except mcp.Err:
        return ""
    p = mcp.prompt_of(lines)
    return mcp.clean(p[0] if p else "\n".join([l for l in lines if l.strip()][-25:]))[-SCREEN_MAX:]


def watch_check(tasks):
    import mcp
    rows = None
    try:
        if FAKE:
            mcp.PROJECTS = FAKE + "/projects"
            with open(FAKE + "/roll.json") as f:
                rows = [r for r in json.load(f) if isinstance(r, dict)]
        else:
            rows = mcp.roll()
    except (mcp.Err, OSError, ValueError):
        pass   # no roll call this time: every task is "unknown", the brain keeps its last verdict
    by = {r.get("sid"): r for r in rows or []}
    out = []
    for t in tasks if isinstance(tasks, list) else []:
        sid, marker = t.get("sid") if isinstance(t, dict) else None, t.get("marker") if isinstance(t, dict) else None
        if not (isinstance(sid, str) and UUID.fullmatch(sid) and isinstance(marker, int) and not isinstance(marker, bool) and marker >= 0):
            continue
        o = {"sid": sid, "marker": marker, "state": "unknown", "size": 0, "name": "", "text": "", "prompt": ""}
        r = by.get(sid)
        if rows is None:
            pass
        elif r is None:
            o["state"] = "gone"
            o["size"], _seen, o["text"] = reply_since(sid, marker, t.get("sent", ""))
        else:
            o["name"] = mcp.one_line(r.get("name", ""), 80)
            if r["state"] == "blocked":
                o["state"] = "blocked"
                if t.get("prompt"):
                    o["prompt"] = blocked_screen(r, rows)
            else:
                seen = False
                if r["state"] == "idle":   # a busy session can only be "working": its transcript (up to 4 MB) is not read
                    o["size"], seen, o["text"] = reply_since(sid, marker, t.get("sent", ""))
                o["state"] = "finished" if seen else "working"   # idle with nothing new yet = the message has not started
        out.append(o)
    return out


def cmd_watch(js):
    print(json.dumps(watch_check(json.loads(js))))


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        {"sessions": cmd_sessions, "transcript": cmd_transcript, "rm": cmd_rm, "folders": cmd_folders, "servers": cmd_servers, "mcpconfig": cmd_mcpconfig,
         "attach": cmd_attach, "attachments": cmd_attachments, "clear-attachments": cmd_clear_attachments, "prune-attachments": cmd_prune_attachments, "watch": cmd_watch}[a[0]](*a[1:])
    except (KeyError, IndexError, TypeError, ValueError):
        sys.exit(64)
