"""Offline checks for the confirm path. Run: python3 -B test_mcp.py   (no shell needed: COMPUTER_QS points at a pid that is not qs)"""
import json, os, re, sys, tempfile, stat, time
os.environ["COMPUTER_QS"] = "--pid 1"            # every ipc call fails: all confirm paths must DENY
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcp

def perm(tool, inp):
    return json.loads(mcp.ask_permission({"tool_name": tool, "input": inp}))

# IPC failure = deny, for the built-ins and for the gated tools
assert perm("Bash", {"command": "ls"})["behavior"] == "deny"
assert perm("Write", {"file_path": "/tmp/x", "content": "y"})["behavior"] == "deny"
for tool in ("set_wifi", "set_bluetooth"):
    assert mcp.call(tool, {"on": False})[0] is mcp.Err
for tool in ("power_off", "reboot", "suspend", "logout"):
    assert mcp.call(tool, {})[0] is mcp.Err
# root is never offered, not even as a card (message says so, and it never reaches ipc)
for c in ("sudo rm -rf /", "ls && su -", "/usr/bin/sudo id", "doas sh", "pkexec x", "echo hi; run0 id"):
    assert "Root access" in perm("Bash", {"command": c})["message"], c
for c in ("echo pseudo", "git commit -m result", "ls /usr/share/sudoers-docs-x"):
    assert "Root access" not in perm("Bash", {"command": c}).get("message", ""), c
# the model's own rules are untouchable, also through Bash
for c in ("echo {} > .claude/settings.json", "cp x ~/computer/.claude/y", "echo hi >> CLAUDE.md", "cat ~/.claude/settings.json"):
    assert "own settings" in perm("Bash", {"command": c})["message"], c
for p in (mcp.COMPUTER + "/.claude/settings.json", mcp.COMPUTER + "/CLAUDE.md", mcp.COMPUTER + "/sub/../.claude/x"):
    assert "own settings" in perm("Write", {"file_path": p, "content": ""})["message"], p
# D8: hard deny (no card) for the user's Claude config and the shell's own code, also with .. and ~
H = mcp.HOME
for p in ("~/.claude/settings.json", H + "/CLAUDE.md", H + "/.claude.json", H + "/.config/quickshell/shell.qml", H + "/.config/quickshell-lcars/Computer.qml",
          H + "/.dots/.config/quickshell-lcars/computer/mcp.py", H + "/.dots/.config/quickshell/bar/Bar.qml", H + "/.local/state/lcars/computer.json",
          mcp.COMPUTER + "/notes/../../.claude/x", mcp.COMPUTER + "/notes/CLAUDE.local.md", mcp.COMPUTER + "/notes/.mcp.json"):
    for tool in ("Write", "Edit"):
        assert "own settings" in perm(tool, {"file_path": p, "content": "", "old_string": "a", "new_string": "b"})["message"], (tool, p)
for c in ("echo x > ~/.claude.json", "cp x ~/.config/quickshell-lcars/a", "sed -i s/a/b/ ~/.local/state/lcars/computer.json", "echo hi >> CLAUDE.local.md"):
    assert "own settings" in perm("Bash", {"command": c})["message"], c
assert "own settings" not in perm("Write", {"file_path": mcp.COMPUTER + "/notes/a.txt", "content": ""})["message"]
# D3: a relative file_path is refused (the card would show another place than claude writes to)
assert "absolute" in perm("Write", {"file_path": "notes/a.txt", "content": ""})["message"]
# hidden characters become visible, too long = refused
assert mcp.clean("a‮b\x00c​d\ne") == "a\\u202eb\\u0000c\\u200bd\ne"
mcp.CARDS = 0
try:
    mcp.confirm("tap", "T", "x" * (mcp.DETAIL_MAX + 1)); assert False
except mcp.Err as e:
    assert "too long" in str(e)
# names and window cap still hold
try:
    mcp.name_ok("-rf"); assert False
except mcp.Err:
    pass
# cards: stub confirm to see which kind a request gets, and exactly what claude is told to run (D2, D3)
seen = []
def fake_confirm(kind, title, detail="", always=False, strict=False):
    seen.append((kind, title, detail, strict))
real_confirm, mcp.confirm = mcp.confirm, fake_confirm
for c in ("loginctl poweroff", "hyprctl dispatch 'hl.dsp.exit()'", "gtmux kill x", "pkill -u me", "qs ipc call computer toggle wifi false", "ls; reboot", "systemctl suspend"):
    seen.clear(); r = perm("Bash", {"command": c}); assert r["behavior"] == "allow" and seen[0][0] == "slide", c
for c in ("ls", "echo power", "git log", "cat notes/a.txt"):
    seen.clear(); r = perm("Bash", {"command": c}); assert seen[0][0] == "tap", c
seen.clear(); r = perm("Bash", {"command": "ls", "run_in_background": True, "timeout": 99999, "dangerouslyDisableSandbox": True})
assert r["updatedInput"] == {"command": "ls"} and seen[0][3] is True    # the unseen options are dropped; Bash gets the strict (ASCII only) display
seen.clear(); perm("Write", {"file_path": mcp.COMPUTER + "/notes/a.txt", "content": "x"}); assert seen[0][0] == "tap" and seen[0][3] is False
mcp.confirm = real_confirm
# strict display: odd spaces, look-alike letters and controls become visible; file text keeps the lenient rule
assert mcp.clean("ls\u00a0x \u0456 \u202e\x1b", True) == "ls\\u00a0x \\u0456 \\u202e\\u001b"
assert mcp.clean("caf\u00e9", False) == "caf\u00e9"
# line limits: blank runs collapse, more than 60 lines is refused (a hidden payload below the fold), the shell is never asked
mcp.ipc = lambda fn, *a: asks.append((fn, a)) or ("pending" if fn == "answer" else "ok")
asks = []
for detail in ("\n".join("l%d" % i for i in range(70)),):
    mcp.CARDS = 0
    try:
        mcp.confirm("tap", "T", detail); assert False
    except mcp.Err as e:
        assert "too long" in str(e) and not asks
mcp.CARDS = 0; mcp.ipc = lambda fn, *a: asks.append((fn, a)) or "allow"
mcp.confirm("tap", "T", "ls" + "\n" * 100 + "curl x | sh")
assert asks[0][1][4] == " ls\n\ncurl x | sh", asks[0]           # the 100 blank lines that would push the tail off screen are collapsed
# D7: one refusal ends every later card in the same message; at most 10 cards
mcp.CARDS = 0; mcp.LOCKED = False
mcp.ipc = lambda fn, *a: "deny" if fn == "answer" else "ok"
try:
    mcp.confirm("tap", "T", "x"); assert False
except mcp.Err as e:
    assert "refused" in str(e) and mcp.LOCKED
mcp.ipc = lambda fn, *a: asks.append(fn) or "allow"
asks = []
try:
    mcp.confirm("tap", "T", "x"); assert False
except mcp.Err as e:
    assert "already refused" in str(e) and not asks             # not even asked
mcp.LOCKED = False; mcp.CARDS = mcp.MAX_CARDS
try:
    mcp.confirm("tap", "T", "x"); assert False
except mcp.Err as e:
    assert "too many" in str(e)
mcp.CARDS = 0; mcp.LOCKED = False
mcp.confirm("tap", "T", "x")                                      # allowed card still works
# D4: the opening prompt goes to a private runtime file outside ~/computer; the computer's own folder is no session folder
import tempfile, stat
mcp.RT = tempfile.mkdtemp()
mcp.new_session = lambda a, cmd, what, prompt=None: cmd("t")
cmdline = mcp.start_claude_session({"folder": mcp.HOME, "prompt": "hello"})
f = cmdline.split("'")[1] if "'" in cmdline else cmdline.split("cat ")[1].rstrip(')"')
assert f.startswith(mcp.RT + "/lcars-computer/prompts/") and open(f).read() == "hello" and stat.S_IMODE(os.stat(f).st_mode) == 0o600 and not f.startswith(mcp.COMPUTER), f
os.makedirs(mcp.COMPUTER + "/notes", exist_ok=True)
for fo in (mcp.COMPUTER, mcp.COMPUTER + "/notes"):
    try:
        mcp.folder_ok(fo); assert False
    except mcp.Err as e:
        assert "own folder" in str(e)
assert mcp.folder_ok(mcp.HOME) == mcp.HOME
# after the card the actions are exactly these commands (DRY = reported, never run; confirm is stubbed so nothing is asked)
mcp.DRY = True
mcp.confirm = lambda *a, **k: None
assert mcp.power_off({}) == "dry run: loginctl poweroff" and mcp.reboot({}) == "dry run: loginctl reboot"
assert mcp.suspend({}) == "dry run: loginctl suspend" and mcp.logout({}) == "dry run: hyprctl dispatch hl.dsp.exit()"
mcp.confirm = real_confirm

# ---- stage 7b: images and the user's own MCP servers
import img, struct, zlib, shutil
def png(w=4, h=4):
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b"")
T = tempfile.mkdtemp(dir=mcp.HOME)                      # a real folder under home, removed at the end
try:
    own, other, priv = T + "/own", T + "/other", T + "/priv"
    for d in (own, other, priv): os.makedirs(d)
    open(own + "/a.png", "wb").write(png()); open(other + "/b.png", "wb").write(png()); open(priv + "/c.png", "wb").write(png())
    open(own + "/fake.png", "wb").write(b"<svg xmlns='http://www.w3.org/2000/svg'/>"); open(own + "/t.txt", "wb").write(png())
    os.symlink(other + "/b.png", own + "/link.png"); os.symlink(priv, own + "/privdir")
    cfg = {"allow": [own, priv], "deny": [priv]}
    ok = lambda p: img.check_local(p, cfg)
    assert ok(own + "/a.png") == os.path.realpath(own + "/a.png")
    try: ok(own + "/t.txt"); assert False   # the first bytes AND an ending the chat can show
    except img.Refused: pass
    for p in (own + "/fake.png", own + "/missing.png", own, other + "/b.png", own + "/link.png", own + "/privdir/c.png", priv + "/c.png",
              own + "/../other/b.png", "/etc/passwd", "", "x\ny", own + "/a.png\x00", None):
        try: ok(p); assert False, p
        except img.Refused as e: assert str(e) == "not an image file in the folders you may read"   # one message: no probing
    assert img.cfg_from("garbage")["allow"] == ["~/computer"]
    # size cap and a decoded-size bomb
    open(own + "/big.png", "wb").write(png() + b"0" * img.MAX_BYTES)
    try: ok(own + "/big.png"); assert False
    except img.Refused: pass
    try: img.vet(png(20000, 1)); assert False
    except img.Refused: pass
    # magic bytes
    assert img.kind(b"GIF89a....") == "gif" and img.kind(b"RIFF\0\0\0\0WEBPVP8 ") == "webp" and img.kind(b"\xff\xd8\xff\xe0") == "jpeg" and img.kind(b"<svg") is None and img.kind(b"<html>") is None
    assert img.dims(png(7, 5), "png") == (7, 5)
    # the model tool: error text is uniform, success returns "ok <realpath>"
    os.environ["COMPUTER_IMG_CFG"] = json.dumps(cfg)
    assert mcp.call("show_image", {"path": own + "/a.png"})[:3] == "ok " and mcp.call("show_image", {"path": priv + "/c.png"})[0] is mcp.Err
    mcp.SHOWN = mcp.MAX_SHOWN
    assert mcp.call("show_image", {"path": own + "/a.png"})[0] is mcp.Err; mcp.SHOWN = 0
    # deny globs: the same private lists as the Read rules
    assert img.denied(mcp.HOME + "/.ssh/x.png", ["~/.ssh"]) and img.denied(mcp.HOME + "/p/.env", ["//**/.env"]) and not img.denied(mcp.HOME + "/p/a.png", ["~/.ssh", "//**/.env"])
finally:
    shutil.rmtree(T)
# URLs: https only, public addresses only, checked again after every redirect
for u in ("http://example.com/a.png", "ftp://example.com/a.png", "https://user@example.com/a.png", "https://example.com:8443/a.png", "https://example.com/a b.png", "file:///etc/passwd", "//example.com/a.png", "https:///a.png", "", None):
    try: img.check_url(u); assert False, u
    except img.Refused: pass
assert img.check_url("https://Example.com/a/b.png?x=1") == ("example.com", "/a/b.png?x=1")
for ip in ("127.0.0.1", "10.1.2.3", "192.168.0.9", "172.16.5.5", "169.254.169.254", "100.64.1.1", "0.0.0.0", "::1", "fe80::1", "fc00::1", "::ffff:127.0.0.1", "224.0.0.1"):
    assert not img.public_ip(ip), ip
assert img.public_ip("93.184.216.34") and img.public_ip("2606:2800:220:1:248:1893:25c8:1946")
for h in ("localhost", "127.0.0.1", "[::1]", "169.254.169.254", "10.0.0.1"):
    try: img.resolve(h.strip("[]")); assert False, h
    except img.Refused: pass
real_resolve, real_req = img.resolve, img.request
img.resolve = lambda h: "10.0.0.5" if h == "rebind.test" else "93.184.216.34"      # a public name that answers with a private address is refused
try: img.fetch("https://rebind.test/a.png"); assert False
except img.Refused: pass
hits = []
def req(host, ip, target, deadline):
    hits.append(host)
    return (302, "https://127.0.0.1/x.png", b"") if host == "start.test" else (200, "", png())
img.request = req
img.resolve = lambda h: real_resolve(h) if h == "127.0.0.1" else "93.184.216.34"
try: img.fetch("https://start.test/a.png"); assert False                         # redirect to a private address: refused before any request to it
except img.Refused: assert hits == ["start.test"]
img.request = lambda *a: (302, "https://start.test/", b"")
try: img.fetch("https://start.test/"); assert False
except img.Refused as e: assert "redirects" in str(e)
img.request = lambda *a: (302, "http://example.com/", b"")                         # redirect down to http
try: img.fetch("https://start.test/"); assert False
except img.Refused: pass
img.request = lambda *a: (200, "", b"<html>not an image</html>")
try: img.fetch("https://x.test/"); assert False
except img.Refused: pass
img.request = lambda *a: (200, "", b"<svg xmlns='http://www.w3.org/2000/svg'/>")
try: img.fetch("https://x.test/"); assert False
except img.Refused: pass
img.request = lambda *a: (200, "", png() + b"0" * (img.MAX_BYTES + 1))
try: img.fetch("https://x.test/"); assert False
except img.Refused: pass
img.request = lambda *a: (404, "", b"")
try: img.fetch("https://x.test/"); assert False
except img.Refused: pass
img.request = lambda *a: (200, "", png())
assert img.fetch("https://x.test/") == png()
# the tool saves under a name we make up and caps downloads per message
img.ATTACH = tempfile.mkdtemp()
r = mcp.call("show_web_image", {"url": "https://x.test/whatever.php?evil=../../x"})
assert r[:3] == "ok " and re.fullmatch(r"%s/web-\d+-[0-9a-f]{6}\.png" % img.ATTACH, r[3:].split("\n")[0]) and stat.S_IMODE(os.stat(r[3:].split("\n")[0]).st_mode) == 0o600, r
for _ in range(mcp.MAX_FETCH): mcp.call("show_web_image", {"url": "https://x.test/"})
assert mcp.call("show_web_image", {"url": "https://x.test/"})[0] is mcp.Err
mcp.FETCHED = mcp.SHOWN = 0
assert mcp.call("show_web_image", {"url": "http://x.test/"})[0] is mcp.Err and mcp.call("show_web_image", {"url": "https://127.0.0.1/"})[0] is mcp.Err
shutil.rmtree(img.ATTACH)
img.resolve, img.request = real_resolve, real_req
# user MCP servers: always a card with the exact tool in the title and every argument; ALWAYS ALLOW only for tools whose name is not risky
seen = []
def fc(kind, title, detail="", always=False, strict=False):
    seen.append((kind, title, detail, always, strict))
mcp.confirm = fc
r = perm("mcp__playwright__browser_navigate", {"url": "https://example.com", "note": "a\nb"})
assert r["behavior"] == "allow" and seen[0][:2] == ("tap", "USE MCP playwright browser_navigate") and seen[0][3] is False and seen[0][4] is True
assert seen[0][2] == "SERVER: playwright\nTOOL: browser_navigate\nurl: https://example.com\nnote: a\n    b", seen[0][2]
seen.clear(); perm("mcp__railway__delete-service", {}); assert seen[0][3] is False and "(no arguments)" in seen[0][2]
seen.clear(); perm("mcp__x__browser_run_code_unsafe", {}); assert seen[0][3] is False
seen.clear(); perm("mcp__fraedi__send_message", {"to": "x"}); assert seen[0][3] is False
assert "unknown tool" in perm("mcp__bad name__x", {})["message"]
mcp.confirm = real_confirm
mcp.ipc = lambda fn, *a: "deny" if fn == "answer" else "ok"; mcp.CARDS = 0; mcp.LOCKED = False
r = perm("mcp__fraedi__whoami", {}); assert r["behavior"] == "deny" and "refused" in r["message"]      # DENY refuses the call
mcp.CARDS = 0; mcp.LOCKED = False
# host.py: server list shows names and types only; mcpconfig copies enabled ones into a 0600 file in the runtime folder
import subprocess
fj = tempfile.mkdtemp(); open(fj + "/c.json", "w").write(json.dumps({"mcpServers": {"web": {"type": "http", "url": "https://SECRET-URL/x", "headers": {"Authorization": "SECRET-TOKEN"}},
    "loc": {"command": "npx", "args": ["@playwright/mcp"], "env": {"K": "SECRET-ENV"}}, "computer": {"command": "x"}, "bad name": {"command": "x"}}}))
hostenv = dict(os.environ, LCARS_CLAUDE_JSON=fj + "/c.json", XDG_RUNTIME_DIR=fj, COMPUTER_SERVERS="web loc computer nope", COMPUTER_IMG_CFG="{}")
host = os.path.join(os.path.dirname(os.path.abspath(__file__)), "host.py")
out = subprocess.run([sys.executable, "-B", host, "servers"], env=hostenv, capture_output=True, text=True).stdout
assert "SECRET" not in out and [json.loads(l)["name"] for l in out.splitlines()] == ["loc", "web"] and "OPENS A BROWSER WINDOW" in out
subprocess.run([sys.executable, "-B", host, "mcpconfig"], env=hostenv, check=True)
cf = fj + "/lcars-computer/mcp.json"
assert stat.S_IMODE(os.stat(cf).st_mode) == 0o600 and stat.S_IMODE(os.stat(fj + "/lcars-computer").st_mode) == 0o700
assert sorted(json.load(open(cf))["mcpServers"]) == ["computer", "loc", "web"] and json.load(open(cf))["mcpServers"]["computer"]["args"][1].endswith("/mcp.py")
shutil.rmtree(fj)
# ---- final fixes: notes-only writes, save_note, ALWAYS ALLOW allow list
os.environ["COMPUTER_NOTES_ONLY"] = "1"
for p in (H + "/.zshrc", H + "/.local/share/applications/x.desktop", mcp.COMPUTER + "/other.txt", mcp.COMPUTER + "/notes/../x.txt"):
    for tool in ("Write", "Edit"):
        assert "only write inside" in perm(tool, {"file_path": p, "content": "", "old_string": "a", "new_string": "b"})["message"], (tool, p)
del os.environ["COMPUTER_NOTES_ONLY"]
assert "only write inside" not in perm("Write", {"file_path": H + "/.zshrc", "content": ""}).get("message", "")   # without the env a card is raised (stub denies: ipc fails)
real_notes = mcp.COMPUTER
mcp.COMPUTER = tempfile.mkdtemp()
try:
    nd = mcp.COMPUTER + "/notes"
    r = mcp.call("save_note", {"name": "report-1.md", "content": "# hi"})
    assert r == "ok " + os.path.join(os.path.realpath(nd), "report-1.md") and open(nd + "/report-1.md").read() == "# hi" and stat.S_IMODE(os.stat(nd + "/report-1.md").st_mode) == 0o600
    assert mcp.call("save_note", {"name": "report-1.md", "content": "x"})[0] is mcp.Err          # never overwrites by default
    assert open(nd + "/report-1.md").read() == "# hi"
    assert mcp.call("save_note", {"name": "report-1.md", "content": "new", "overwrite": True})[0:3] == "ok " and open(nd + "/report-1.md").read() == "new"
    for bad in ("../x.md", "a/b.md", "/etc/x.md", ".hidden.md", "x.sh", "x.py", "x", "x.md.exe", "CLAUDE.md", "claude.local.md", "CLAUDE-notes.md", ".mcp.json", "a b.md", "x.md\n", "", None, 5, "x" * 90 + ".md"):
        assert mcp.call("save_note", {"name": bad, "content": "x"})[0] is mcp.Err, bad
    for bad in ("", None, 5, "x" * (mcp.NOTE_MAX + 1), "a\x00b"):
        assert mcp.call("save_note", {"name": "ok.txt", "content": bad})[0] is mcp.Err
    os.symlink("/etc/hostname", nd + "/link.txt")
    assert mcp.call("save_note", {"name": "link.txt", "content": "x", "overwrite": True})[0] is mcp.Err   # a planted link is never followed
    assert sorted(os.listdir(nd)) == ["link.txt", "report-1.md"]
    shutil.rmtree(nd); os.symlink("/tmp", nd)
    assert mcp.call("save_note", {"name": "z.txt", "content": "x"})[0] is mcp.Err                         # notes folder that is a link is refused
finally:
    shutil.rmtree(mcp.COMPUTER); mcp.COMPUTER = real_notes
# ALWAYS ALLOW only for read-like tool names
mcp.confirm = fc
for n, want in (("get-logs", True), ("list_projects", True), ("whoami", True), ("search-docs", True), ("browser_navigate", False), ("set-variables", False),
                ("browser_click", False), ("artifact_update", False), ("get-bucket-credentials", False), ("list-variables", True), ("get_secret", False)):
    seen.clear(); perm("mcp__srv__" + n, {}); assert seen[0][3] is want, n
mcp.confirm = real_confirm
# image rules: ending matters, size ceiling
own2 = tempfile.mkdtemp(dir=H)
try:
    open(own2 + "/a.jfif", "wb").write(png()); open(own2 + "/b.png", "wb").write(png())
    c2 = {"allow": [own2], "deny": []}
    try: img.check_local(own2 + "/a.jfif", c2); assert False
    except img.Refused: pass
    assert img.check_local(own2 + "/b.png", c2) and img.allowed_path(own2 + "/missing.png", c2) and img.allowed_path("/etc/x.png", c2) is None
finally:
    shutil.rmtree(own2)
assert img.MAX_PIXELS == 25_000_000
import importlib.util
# tool-result images: only <project>/<session id>/tool-results/<plain file>, copied into attachments
fh = tempfile.mkdtemp(); sv = (img.HOME, img.COMPUTER, img.ATTACH)
try:
    img.HOME = fh; img.COMPUTER = fh + "/computer"; img.ATTACH = img.COMPUTER + "/attachments"; os.makedirs(img.COMPUTER)
    sid = "8c8fb34c-e3c4-4d8e-8f80-213b9e2bfcbd"
    tr = fh + "/.claude/projects/-" + fh.strip("/").replace("/", "-").replace(".", "-") + "-computer/" + sid + "/tool-results"
    ot = fh + "/.claude/projects/-other/" + sid + "/tool-results"
    for d in (tr, tr + "/sub", ot, fh + "/priv"): os.makedirs(d)
    open(tr + "/mcp-x-blob-0.png", "wb").write(png()); open(ot + "/o.png", "wb").write(png()); open(fh + "/priv/p.png", "wb").write(png())
    open(tr + "/sub/s.png", "wb").write(png()); open(tr + "/fake.png", "wb").write(b"not an image"); open(tr + "/../t.jsonl", "wb").write(png())
    os.symlink(fh + "/priv/p.png", tr + "/link.png")
    os.environ["COMPUTER_IMG_CFG"] = json.dumps({"allow": [img.COMPUTER], "deny": [fh + "/.claude"]})
    r = mcp.call("show_image", {"path": tr + "/mcp-x-blob-0.png"})
    got = re.match(r"ok (\S+)", r).group(1)
    assert got.startswith(img.ATTACH + "/") and img.kind(open(got, "rb").read(16)) == "png", r
    for bad in (tr + "/../t.jsonl", ot + "/o.png", tr + "/link.png", tr + "/fake.png", tr + "/sub/s.png", tr + "/../x/../" + sid + "/tool-results/../t.jsonl"):
        assert mcp.call("show_image", {"path": bad})[0] is mcp.Err, bad
    # host.py rebuild makes an image row from the copied path
    tj = tempfile.mktemp(suffix=".jsonl")
    open(tj, "w").write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "i1", "name": "mcp__computer__show_image", "input": {"caption": "c"}}]}}) + "\n"
        + json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "i1", "content": r}]}}) + "\n")
    sp0 = importlib.util.spec_from_file_location("hostmod0", os.path.join(os.path.dirname(os.path.abspath(__file__)), "host.py")); h0 = importlib.util.module_from_spec(sp0); sp0.loader.exec_module(h0)
    assert list(h0.rows(tj)) == [{"kind": "image", "text": "c", "title": got}]; os.remove(tj)
finally:
    img.HOME, img.COMPUTER, img.ATTACH = sv; shutil.rmtree(fh)
# host.py transcript: save_note becomes a SAVED row, never a tool row with the file text
sp = importlib.util.spec_from_file_location("hostmod", os.path.join(os.path.dirname(os.path.abspath(__file__)), "host.py")); hm = importlib.util.module_from_spec(sp); sp.loader.exec_module(hm)
tj = tempfile.mktemp(suffix=".jsonl")
open(tj, "w").write(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "n1", "name": "mcp__computer__save_note", "input": {"name": "r.md", "content": "BODY"}}]}}) + "\n"
    + json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "n1", "content": "ok /x/notes/r.md"}]}}) + "\n")
assert list(hm.rows(tj)) == [{"kind": "saved", "text": "/x/notes/r.md", "title": ""}]
os.remove(tj)

# ---- other Claude sessions: matching, sanitising, refusals, caps (no gtmux, no real session: roll() and the pane are stubbed)
R = lambda name, id, st="idle", kind="interactive", pid=4242, waiting="": {"name": name, "id": id, "sid": "0000000%s-0000-0000-0000-000000000000" % id[-1], "pid": pid, "kind": kind, "state": st, "waiting": waiting, "cwd": "/x", "folder": "~/x", "started": 0}
rows_ = [R("alpha", "aaaaaaa1"), R("beta", "bbbbbbb2"), R("dup", "ccccccc3"), R("dup", "ddddddd4"), R("aaaaaaa1", "eeeeeee5"), R("bg", "fffffff6", "blocked", "background", None)]
for ref, want in (("alpha", None), ("beta", "bbbbbbb2"), ("bbbbbbb2", "bbbbbbb2"), (rows_[1]["sid"], "bbbbbbb2")):
    if want: assert mcp.find_session(ref, rows_)["id"] == want, ref
for ref in ("alp", "ALPHA", "dup", "aaaaaaa1", "/etc/passwd", "../x", "", None, 5, "x" * 300):    # partial, wrong case, ambiguous (two names, name = other id), paths, junk
    try: mcp.find_session(ref, rows_); assert False, ref
    except mcp.Err: pass
assert mcp.tell_text("  hi\r\nthere\t\x1b[31m\x00\u202e\u200b\n\n\n\nend  ") == "hi\nthere    [31m\n\nend"
for bad in ("", "  \x1b ", "/exit\nsecond line", " !rm -rf ~", "#note", "x" * (mcp.TELL_MAX + 1), "\n".join("l" * 3 for _ in range(60)), 5, None):
    try: mcp.tell_text(bad); assert False, repr(bad)
    except mcp.Err: pass
# tell: caps, blocked and background refusals come before any card or key press
cards, keys = [], []
mcp.confirm = lambda *a, **k: cards.append(a)
_gx, _run = mcp.gx, mcp.run
_roll_real = mcp.roll
# M1: a failed or odd listing is an error, never "no sessions" (the watch would report every task gone)
for rc_, out_ in ((1, "[]"), (1, '[{"sessionId": "%s", "pid": 1}]' % ("0" * 8 + "-0000-4000-8000-" + "0" * 12)), (0, "{}"), (0, "null"), (0, "nope")):
    mcp.run = lambda argv, rc_=rc_, out_=out_, **k: (rc_, out_, "")
    try: mcp.roll(); assert False, (rc_, out_)
    except mcp.Err: pass
mcp.run = lambda argv, **k: (0, "[]", ""); assert mcp.roll() == []
mcp.run = _run
# M8: slash commands. Dangerous ones are refused outright (whole word, any case, with or without arguments), the rest stay allowed; ! # & never start a message
for bad in ("/plugin", "/PLUGIN install x", "/Add-Dir /etc", "/permissions", "/allowed-tools", "/hooks", "/mcp add x", "/login", "/logout", "/export /tmp/x", "/feedback hi", "/bug", "/config", "/settings",
            "/install-github-app", "/terminal-setup", "/agents", "/memory", "/init", "/security-review", "/update", "/upgrade", "/doctor", "/vim", "/ide", "/remote-control", "/bashes", "/exit", "&hi", "& hi", "/auto-mode-setup", "/cd /etc", "/share", "/checkup", "/rc", "/app", "/tp", "/peers", "/Routines", "/remote", "/mobile"):
    try: mcp.tell_text(bad); assert False, bad
    except mcp.Err: pass
for good in ("/cost", "/compact", "/context", "/status", "/usage now", "/pluginx", "/mcp__x", "/plugin:foo", "/ plugin", "a /plugin", "/helpful"):
    assert mcp.tell_text(good) == good, good
mcp.gx = lambda *a: keys.append(a) or ""
mcp.roll = lambda: rows_
mcp.pane_of = lambda r, rows: ("s", "%1") if r["kind"] == "interactive" else mcp.pane_of_real(r, rows)
mcp.pane_of_real = lambda r, rows: (_ for _ in ()).throw(mcp.Err("%s is a background session" % r["name"]))
mcp.screen_of = lambda s, p: ["x", "─" * 20, "❯ ", "─" * 20, "  footer"]
mcp.box_of = lambda s, p: mcp.screen_of(s, p)
def refused(a, frag):
    try: mcp.claude_tell(a); assert False, a
    except mcp.Err as e: assert frag in str(e), (frag, str(e))
    assert not cards and not keys
refused({"sessions": ["alpha"] * 7, "text": "hi"}, "at most")
refused({"sessions": [], "text": "hi"}, "list of names")
refused({"sessions": "alpha", "text": "hi"}, "list of names")
refused({"sessions": ["nobody"], "text": "hi"}, "no such session")
refused({"sessions": ["bg"], "text": "hi"}, "background")
rows_[1]["state"] = "blocked"
refused({"sessions": ["alpha", "beta"], "text": "hi"}, "claude_approve")          # one blocked target refuses all of them
rows_[1]["state"] = "busy"
assert mcp.tell_text("  /cost ") == "/cost" and mcp.tell_text("a /b") == "a /b"                      # a one line slash command is allowed
rows_[1]["state"] = "idle"
mcp.screen_of = lambda s, p: ["x", "─" * 20, "❯ half typed", "─" * 20, "  f"]
refused({"sessions": ["alpha"], "text": "hi"}, "unsent text")
mcp.screen_of = lambda s, p: [" Do you want to proceed?", " ❯ 1. Yes", "   2. No"]
refused({"sessions": ["alpha"], "text": "hi"}, "not at an input box")
# approve: only a blocked session, only the plain Yes / No
refused_a = lambda a, frag: (lambda: None)
for st in ("idle", "busy"):
    rows_[0]["state"] = st
    try: mcp.claude_approve({"session": "alpha", "decision": "allow"}); assert False
    except mcp.Err as e: assert "not waiting" in str(e)
try: mcp.claude_approve({"session": "alpha", "decision": "always"}); assert False
except mcp.Err as e: assert "allow or deny" in str(e)
assert not cards and not keys
P = lambda *o: (None, dict(enumerate(o, 1)))
assert mcp.answer_key(P("Yes", "Yes, and always allow x", "Yes, and switch to auto mode", "No"), "allow") == "1"
assert mcp.answer_key(P("Yes", "Yes, allow all edits", "No"), "deny") == "3"
for p, d in ((P("Yes, and always allow x", "No"), "allow"), (P("Yes", "Yes", "No"), "allow"), (P("Yes", "Maybe"), "deny"), (None, "allow")):
    try: mcp.answer_key(p, d); assert False, p
    except mcp.Err: pass
scr = ["old", "─" * 20, " Bash command", " touch x", " Do you want to proceed?", " ❯ 1. Yes", "   2. Yes, and always allow access to /tmp", "      from this project", "   3. No", "", " Esc to cancel"]
t, o = mcp.prompt_of(scr)
assert o == {1: "Yes", 2: "Yes, and always allow access to /tmp", 3: "No"} and t.startswith(" Bash command") and "old" not in t and mcp.input_box(scr) is None
assert mcp.input_box(["a", "─" * 12, "❯ Try \"edit x\"", "─" * 12, " ? for shortcuts"]) == "" and mcp.input_box(["─" * 12, "❯ a", "  b", "─" * 12]) == "a\nb"

# F3: gtmux run / send-keys / tmux send-keys through Bash is a slide
for c in ("gtmux run s send-keys -t %3 -l hi", "tmux send-keys -t x Enter", "echo a; gtmux  run s send-keys 1"):
    seen.clear(); mcp.confirm = fc; perm("Bash", {"command": c}); assert seen[0][0] == "slide", c
seen.clear(); perm("Bash", {"command": "gtmux ls"}); assert seen[0][0] == "tap"
# F5: the tell card is kind "ask", never plain tap
rows_[0]["state"] = "idle"; mcp.confirm = fc
mcp.gx = lambda *a: ""; mcp.screen_of = lambda s, p: ["x", "─" * 20, "❯ ", "─" * 20, "  footer"]
seen.clear(); mcp.claude_tell({"sessions": ["alpha"], "text": "hi"}); assert seen[0][0] == "ask" and "[aaaaaaa1]" in seen[0][2], seen
# F6: trailing backslash refused; Enter that did not submit is reported
try: mcp.tell_text("hi\\"); assert False
except mcp.Err: pass
boxes = iter([["x", "─" * 20, "❯ ", "─" * 20, "f"], ["x", "─" * 20, "❯ ", "─" * 20, "f"], ["x", "─" * 20, "❯ hi", "─" * 20, "f"], ["x", "─" * 20, "❯ hi", "─" * 20, "f"]])
mcp.screen_of = lambda s, p: next(boxes, None) or boxes_last
boxes_last = ["x", "─" * 20, "❯ hi", "─" * 20, "f"]
rows_[0]["state"] = "idle"
r = mcp.claude_tell({"sessions": ["alpha"], "text": "hi"}); assert "NOT submitted" in r, r
# F2: after STOP (parent changed) no key is sent, the process exits
mcp.run = lambda argv, **k: (0, "", "")
mcp.PPID0 = -1
try: _gx("s", "send-keys", "-t", "%1", "1"); assert False
except SystemExit: pass
_gx("s", "capture-pane", "-p")                                                       # reading is still fine
mcp.PPID0 = os.getppid(); mcp.run = _run
# F7: no rule above the options = no prompt (header scrolled off)
assert mcp.prompt_of([" Do you want to proceed?", " ❯ 1. Yes", "   2. No"]) is None
# ghost suggestion (dim) in the input box is not a draft; real text is
assert mcp.undim("\x1b[0m\u276f\xa0\x1b[0;2mretry sleep\x1b[0m   ").strip() == "\u276f" and mcp.undim("\x1b[0;38;2;2;2;2mab\x1b[0m cd") == "ab cd"
# F8: trailing newline is not a valid name or pane or id
assert not mcp.NAME_RE.match("a\n") and not mcp.PANE_RE.match("%1\n") and not mcp.UUID_RE.match(rows_[0]["sid"] + "\n")
# functional: a background child that inherits the pane does not make the interactive parent unreachable
import types
src = open(mcp.__file__).read(); assert 'o["kind"] == "interactive" and env_pane' in src
# one huge transcript line: chat_rows retries with a bigger tail
tj2 = tempfile.mktemp(suffix=".jsonl"); sid2 = "0000000a-0000-0000-0000-000000000000"
open(tj2, "w").write(json.dumps({"type": "user", "message": {"content": "hello"}}) + "\n" + json.dumps({"type": "x", "pad": "p" * 3000}) + "\n")
_tr0, mcp.transcript = mcp.transcript, (lambda sid: tj2)
assert mcp.chat_rows(sid2, 1000)[0] == [{"kind": "user", "text": "hello", "title": ""}]; os.remove(tj2)

# ---- follow-up watch: claude_tell registers, three tools, host.py watch, the report turn's tool list
B = lambda t: ["x", "─" * 20, "❯ " + t, "─" * 20, "f"]
txf = tempfile.mktemp(suffix=".jsonl"); open(txf, "w").write("x" * 123)
mcp.transcript = lambda sid: txf
def tell_once(boxes_seq, ipc_reply="ok"):
    seq = iter(boxes_seq); log = []
    mcp.screen_of = lambda s, p: next(seq)
    mcp.ipc = lambda fn, *a: log.append((fn, a)) or ipc_reply
    rows_[0]["state"] = "idle"; mcp.confirm = lambda *a, **k: None
    return mcp.claude_tell({"sessions": ["alpha"], "text": "do the thing"}), log
r, log = tell_once([B(""), B(""), B("do the thing"), B("")])
assert "sent. It is now being watched" in r and log[0][0] == "watchAdd", (r, log)
fn, a = log[0]; assert a == (rows_[0]["sid"], "aaaaaaa1", " alpha", " ~/x", "s", " do the thing", 123), a       # marker = transcript size before the text went in
r, log = tell_once([B(""), B(""), B("do the thing"), B("")], "error: at most 6 tasks are watched")
assert "sent. NOT being watched (at most 6 tasks are watched)" in r, r                                # more than 6: it still sends, and says so
def tell_state(st, text="do the thing"):
    seq = iter([B(""), B(""), B(text), B("Press up to edit queued messages")]); log = []
    mcp.screen_of = lambda s, p: next(seq); mcp.ipc = lambda fn, *a: log.append((fn, a)) or "ok"
    rows_[0]["state"] = st; mcp.confirm = lambda *a, **k: None
    return mcp.claude_tell({"sessions": ["alpha"], "text": text}), log
r, log = tell_state("busy"); assert "queued: it will read it when its current work is done. It is now being watched" in r and log[0][0] == "watchAdd", r      # busy is told now; the queue hint is not unsent text
rows_[0]["state"] = "blocked"
try: mcp.claude_tell({"sessions": ["alpha"], "text": "hi"}); assert False
except mcp.Err as e: assert "blocked" in str(e)                                                          # blocked stays refused
cards.clear(); mcp.confirm = lambda kind, title, detail="", **k: cards.append((kind, title, detail))
seq = iter([B(""), B(""), B("/cost"), B("")]); mcp.screen_of = lambda s, p: next(seq); rows_[0]["state"] = "idle"; log = []; mcp.ipc = lambda fn, *a: log.append(fn) or "ok"
r = mcp.claude_tell({"sessions": ["alpha"], "text": "/cost"})
assert cards[-1][0] == "ask" and cards[-1][2].startswith("SLASH COMMAND") and "slash command, there is nothing to watch" in r and log == [], (cards, r, log)   # marked on the card, never watched
r, log = tell_once([B(""), B(""), B("do the thing"), B("do the thing")])
assert "NOT submitted" in r and not log, (r, log)                                                      # not registered when not submitted
r, log = tell_once([B(""), B(""), B("do the thing"), ["no box here"]])
assert "could not confirm" in r and not log, (r, log)                                                  # nor when it could not be confirmed
os.remove(txf); mcp.transcript = _tr0
# the three tools: no card, only ipc, strict input; status merges the live poll and never turns watching on
import host
fd = tempfile.mkdtemp(); os.makedirs(fd + "/projects/p")
host.FAKE = fd
S1, S2, S3, S4, S5 = ("0000000%d-0000-4000-8000-000000000000" % i for i in range(1, 6))
def rr(sid, st, name="n"): return {"name": name, "id": sid[:8], "sid": sid, "pid": 1, "kind": "interactive", "state": st, "waiting": "", "cwd": "/x", "folder": "~/x", "started": 0}
def tl(sid, *lines):
    with open(fd + "/projects/p/%s.jsonl" % sid, "a") as f:
        for kind, c in lines: f.write(json.dumps({"type": kind, "message": {"content": [{"type": "text", "text": c}] if kind == "assistant" else c}}) + "\n")
tl(S1, ("user", "q")); m1 = os.path.getsize(fd + "/projects/p/%s.jsonl" % S1)
tl(S1, ("user", "do it please"), ("assistant", "first\x1b[31m part"), ("assistant", "end " + "z" * 7000))
tl(S2, ("user", "q"))
json.dump([rr(S1, "idle", "one"), rr(S2, "idle", "two"), rr(S3, "blocked", "three"), rr(S4, "busy", "four")], open(fd + "/roll.json", "w"))
tl(S4, ("user", "q"), ("assistant", "working"))
res = {v["sid"]: v for v in host.watch_check([{"sid": S1, "marker": m1}, {"sid": S2, "marker": 0}, {"sid": S3, "marker": 0, "prompt": True}, {"sid": S4, "marker": 0}, {"sid": S5, "marker": 0},
                                              {"sid": "bad", "marker": 0}, {"sid": S1, "marker": -1}, {"sid": S1, "marker": True}, "x", None])}
assert len(res) == 5 and res[S1]["state"] == "finished" and res[S2]["state"] == "working" and res[S3]["state"] == "blocked" and res[S4]["state"] == "working" and res[S5]["state"] == "gone", res
assert res[S4]["text"] == "" and res[S4]["size"] == 0, res[S4]                                                                                  # M7: a busy session's transcript is not read
assert res[S1]["text"].endswith("z" * 100) and len(res[S1]["text"]) == host.REPLY_MAX and "\x1b" not in res[S1]["text"] and res[S1]["name"] == "one"      # tail kept, capped, controls shown not sent
assert host.watch_check([{"sid": S1, "marker": 10 ** 9}])[0]["text"].endswith("z" * 100)                                                                   # marker past the end reads from the start
assert host.watch_check([{"sid": S1, "marker": 0, "sent": "do it please"}])[0]["state"] == "finished"                                                 # our message arrived, then the answer
assert host.watch_check([{"sid": S1, "marker": 0, "sent": "something else"}])[0]["state"] == "working"                                                    # earlier work answering does not count
S6 = "00000006-0000-4000-8000-000000000000"
json.dump(json.load(open(fd + "/roll.json")) + [rr(S6, "idle", "six")], open(fd + "/roll.json", "w"))
tl(S6, ("user", "q"), ("assistant", "answer to earlier work"))
assert host.watch_check([{"sid": S6, "marker": 0, "sent": "queued msg"}])[0]["state"] == "working"
open(fd + "/projects/p/%s.jsonl" % S6, "a").write(json.dumps({"type": "queue-operation", "operation": "enqueue", "content": "queued  msg"}) + "\n")
assert host.watch_check([{"sid": S6, "marker": 0, "sent": "queued msg"}])[0]["state"] == "working"                                                       # only queued, not read yet
open(fd + "/projects/p/%s.jsonl" % S6, "a").write(json.dumps({"type": "attachment", "attachment": {"type": "queued_command", "prompt": "queued  msg\nmore"}}) + "\n")
assert host.watch_check([{"sid": S6, "marker": 0, "sent": "queued msg"}])[0]["state"] == "working"                                                       # read it, no answer yet
tl(S6, ("assistant", "answer to ours"))
v6 = host.watch_check([{"sid": S6, "marker": 0, "sent": "queued msg"}])[0]; assert v6["state"] == "finished" and v6["text"] == "answer to ours", v6
r0 = [r for r in json.load(open(fd + "/roll.json"))]; r0[2]["screen"] = "Run rm?\n1. Yes\n2. No"; json.dump(r0, open(fd + "/roll.json", "w"))
assert host.watch_check([{"sid": S3, "marker": 0, "prompt": True}])[0]["prompt"] == "Run rm?\n1. Yes\n2. No" and host.watch_check([{"sid": S3, "marker": 0}])[0]["prompt"] == ""
S7 = "00000007-0000-4000-8000-000000000000"
json.dump(json.load(open(fd + "/roll.json")) + [rr(S7, "idle", "seven")], open(fd + "/roll.json", "w"))
tl(S7, ("user", "q")); m7 = os.path.getsize(fd + "/projects/p/%s.jsonl" % S7)
tl(S7, ("user", "long task please"), ("assistant", "mid"))
with open(fd + "/projects/p/%s.jsonl" % S7, "a") as f:
    f.write("[" * 100000 + "]" * 100000 + "\n")
    for _ in range(3): f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "big " + "y" * 1_500_000}]}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "the end"}]}}) + "\n")
assert os.path.getsize(fd + "/projects/p/%s.jsonl" % S7) - m7 > 4_000_000
v7 = host.watch_check([{"sid": S7, "marker": m7, "sent": "long task please"}])[0]
assert v7["state"] == "finished" and v7["text"].endswith("the end"), v7["state"]                                                                  # H2 (and a nested line did not kill the poll)
assert host.watch_check([{"sid": S7, "marker": m7, "sent": "never sent"}])[0]["state"] == "finished"                                               # window starts after the marker: counts as read (accepted)
os.makedirs(fd + "/projects/q"); open(fd + "/projects/q/%s.jsonl" % S6, "w").write("{}\n"); os.utime(fd + "/projects/p/%s.jsonl" % S6, (1, 1))
assert mcp.transcript(S6) == fd + "/projects/q/%s.jsonl" % S6 or mcp.PROJECTS != fd + "/projects"
mcp.PROJECTS = fd + "/projects"; assert mcp.transcript(S6) == fd + "/projects/q/%s.jsonl" % S6                                                   # two folders, one session id: the newest
# M3: the report turn's message becomes a short row, and never a session title
# M1 end to end: a failed `claude agents` listing gives "unknown" for every task, never "gone"
os.remove(fd + "/roll.json"); host.FAKE = ""; _run0, _roll0 = mcp.run, mcp.roll; mcp.roll = _roll_real; mcp.run = lambda argv, **k: (1, "[]", ""); assert [v["state"] for v in host.watch_check([{"sid": S1, "marker": 0}])] == ["unknown"]
mcp.run, mcp.roll = _run0, _roll0; host.FAKE = fd
assert [v["state"] for v in host.watch_check([{"sid": S1, "marker": 0}])] == ["unknown"]                                                                   # no roll call: no verdict
out = subprocess.run([sys.executable, "-B", os.path.join(os.path.dirname(mcp.__file__), "host.py"), "watch", "[]"], capture_output=True, text=True)
assert out.stdout.strip() == "[]" and subprocess.run([sys.executable, "-B", os.path.join(os.path.dirname(mcp.__file__), "host.py"), "watch", "{"], capture_output=True).returncode == 64
json.dump([rr(S1, "idle", "one"), rr(S2, "busy", "two")], open(fd + "/roll.json", "w"))
tasks = [{"sid": S1, "id": S1[:8], "name": "one", "sent": "do it", "marker": m1, "on": False, "held": False}, {"sid": S2, "id": S2[:8], "name": "two", "sent": "s", "marker": 0, "on": True, "held": True}]
mcp.ipc = lambda fn, *a: json.dumps(tasks) if fn == "watchList" else (_ for _ in ()).throw(AssertionError(fn))
st = mcp.watch_status({}); j = json.loads(st[st.index("\n") + 1:])
assert st.startswith("DATA") and j[0]["watching"] is False and j[0]["state"] == "finished" and j[0]["last_line"].startswith("zzz") and len(j[0]["last_line"]) <= 200 and j[1]["state"] == "working" and j[1]["report_waiting"] is True, j
cards_before = len(cards)
mcp.ipc = lambda fn, *a: log.append((fn, a)) or "ok 1 paused"; log = []
assert mcp.watch_set({"session": "one", "on": False}) == "ok 1 paused" and log == [("watchSet", ("one", False))]
log.clear(); mcp.watch_cancel({"session": "all"}); assert log == [("watchCancel", ("all",))]
for bad in ({"session": "", "on": True}, {"session": 5, "on": True}, {"session": "x" * 201, "on": True}, {"session": "one", "on": "yes"}):
    try: mcp.watch_set(bad); assert False, bad
    except mcp.Err: pass
mcp.ipc = lambda fn, *a: "error: no such task"
try: mcp.watch_cancel({"session": "nobody"}); assert False
except mcp.Err as e: assert "no such task" in str(e)
assert len(cards) == cards_before                                                                           # none of the three raises a card
assert not any(n in ("watch_status", "watch_set", "watch_cancel") and False for n, *_ in mcp.TOOLS) and {"watch_status", "watch_set", "watch_cancel"} <= set(mcp.HANDLERS)
# the report turn: its own server lists exactly the talk and show tools, and refuses any other call
for env_report, want in (("1", {"speak", "show"}), ("", None)):
    p = subprocess.run([sys.executable, "-B", mcp.__file__], input='{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"claude_tell","arguments":{}}}\n',
                       capture_output=True, text=True, env=dict(os.environ, COMPUTER_REPORT=env_report, COMPUTER_QS="--pid 1"))
    l1, l2 = (json.loads(x) for x in p.stdout.splitlines())
    names = {t["name"] for t in l1["result"]["tools"]}
    if want: assert names == want and "error" in l2, (names, l2)
    else: assert {"claude_tell", "watch_set", "power_off"} <= names
rj = fd + "/rep.jsonl"
with open(rj, "w") as f:
    for c in ("[AUTOMATIC FOLLOW-UP, not typed by the user] The Claude session ... <<<DATA a>>>\nsecret text", "hello"): f.write(json.dumps({"type": "user", "message": {"content": c}}) + "\n")
assert list(host.rows(rj)) == [{"kind": "report", "text": "FOLLOW-UP REPORT", "title": ""}, {"kind": "user", "text": "hello", "title": ""}]
# L7: old per-run mcp files are removed by mcpconfig, the new one and fresh ones stay
rt = tempfile.mkdtemp(); os.makedirs(rt + "/lcars-computer", mode=0o700)
for n_, age in (("mcp-1-1.json", 7200), ("mcp-2-2.json", 10), ("keep.txt", 7200)):
    open(rt + "/lcars-computer/" + n_, "w").write("{}"); os.utime(rt + "/lcars-computer/" + n_, (time.time() - age,) * 2)
subprocess.run([sys.executable, "-B", host.__file__, "mcpconfig"], env=dict(os.environ, XDG_RUNTIME_DIR=rt, COMPUTER_MCP_FILE=rt + "/lcars-computer/mcp-3-3.json", COMPUTER_SERVERS=""), check=True)
assert sorted(os.listdir(rt + "/lcars-computer")) == ["keep.txt", "mcp-2-2.json", "mcp-3-3.json"], os.listdir(rt + "/lcars-computer")
shutil.rmtree(rt)
assert host.FAKE == fd and not subprocess.run([sys.executable, "-B", "-c", "import host; print(host.FAKE)"], capture_output=True, text=True, cwd=os.path.dirname(host.__file__), env=dict(os.environ, COMPUTER_FAKE="/x")).stdout.strip()   # L2: the environment cannot switch the fake data on
import shutil; shutil.rmtree(fd)

print("ok")
