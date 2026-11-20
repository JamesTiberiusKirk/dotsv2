"""Image rules shared by mcp.py (the model's tools), host.py (chat rebuild, attachments) and the tests. Stdlib only.
Nothing here trusts a path, a URL or a file extension from the model: files are judged by their first bytes, paths by their real location."""
import fnmatch, http.client, ipaddress, json, os, re, secrets, socket, ssl, struct, time, urllib.parse

HOME = os.path.realpath(os.path.expanduser("~"))
COMPUTER = os.path.join(HOME, "computer")
ATTACH = os.path.join(COMPUTER, "attachments")
MAX_BYTES = 10_000_000          # one image file
MAX_SIDE, MAX_PIXELS = 16000, 25_000_000   # decoded size: a small file can still be a memory bomb
EXT = {"png": "png", "jpeg": "jpg", "gif": "gif", "webp": "webp"}   # no svg: it can pull in other files


class Refused(Exception):
    pass


def kind(b):
    """png / jpeg / gif / webp from the first bytes, else None."""
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if b[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if b[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if b[:4] == b"RIFF" and b[8:12] == b"WEBP":
        return "webp"
    return None


def dims(b, k):
    """(width, height) from the headers, or None."""
    try:
        if k == "png":
            return struct.unpack(">II", b[16:24])
        if k == "gif":
            return struct.unpack("<HH", b[6:10])
        if k == "webp":
            t = b[12:16]
            if t == b"VP8 ":
                return struct.unpack("<HH", b[26:30])[0] & 0x3FFF, struct.unpack("<HH", b[26:30])[1] & 0x3FFF
            if t == b"VP8L":
                v = struct.unpack("<I", b[21:25])[0]
                return (v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1
            if t == b"VP8X":
                return int.from_bytes(b[24:27], "little") + 1, int.from_bytes(b[27:30], "little") + 1
            return None
        if k == "jpeg":
            i = 2
            while i + 9 < len(b):
                if b[i] != 0xFF:
                    i += 1
                    continue
                m = b[i + 1]
                if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7 or m == 0xFF:
                    i += 1 if m == 0xFF else 2
                    continue
                n = struct.unpack(">H", b[i + 2:i + 4])[0]
                if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
                    h, w = struct.unpack(">HH", b[i + 5:i + 9])
                    return w, h
                i += 2 + n
    except struct.error:
        return None
    return None


def vet(b):
    """Bytes of an image we are willing to show: returns the kind or raises Refused."""
    k = kind(b[:16])
    if k is None or len(b) > MAX_BYTES:
        raise Refused("not an allowed image")
    d = dims(b, k)
    if not d or d[0] < 1 or d[1] < 1 or max(d) > MAX_SIDE or d[0] * d[1] > MAX_PIXELS:
        raise Refused("image size not allowed")
    return k


# ---------------------------------------------------------------- local files
def cfg_from(s):
    """{"allow": [folders], "deny": [globs]} from the brain (env COMPUTER_IMG_CFG). Missing or broken = only ~/computer."""
    try:
        j = json.loads(s or "")
        allow, deny = [str(x) for x in j.get("allow", [])], [str(x) for x in j.get("deny", [])]
    except (ValueError, AttributeError, TypeError):
        allow, deny = ["~/computer"], []
    return {"allow": allow or ["~/computer"], "deny": deny}


def _ex(p):
    p = os.path.expanduser(p)
    return "/" + p.lstrip("/") if p.startswith("//") else p      # claude's "//x" = absolute /x


def inside(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")


def denied(path, deny):
    """The same private / never-write lists the Read rules use (globs allowed, a folder covers everything below it)."""
    for pat in deny:
        pat = _ex(re.sub(r"/\*\*$", "", pat))
        if fnmatch.fnmatchcase(path, pat) or fnmatch.fnmatchcase(path, pat + "/*"):
            return True
        real = os.path.realpath(pat) if "*" not in pat else pat
        if inside(path, real):
            return True
    return False


def allowed_path(path, cfg):
    """Real path when it lies inside an allowed folder and no deny rule covers it (the file need not exist), else None."""
    p = _ex(path)
    p = os.path.realpath(p if os.path.isabs(p) else os.path.join(COMPUTER, p))      # symlinks and .. are resolved BEFORE the checks
    roots = [os.path.realpath(_ex(a)) for a in cfg["allow"]]
    return p if any(inside(p, r) for r in roots) and not denied(p, cfg["deny"]) else None


def check_local(path, cfg):
    """Real path of an image the model may show, else Refused. One message for every failure: it must not work as a file probe."""
    no = Refused("not an image file in the folders you may read")
    if not isinstance(path, str) or not path or len(path) > 1000 or "\x00" in path or "\n" in path:
        raise no
    p = allowed_path(path, cfg)
    if p is None or not re.search(r"\.(png|jpe?g|gif|webp)$", p, re.I):   # the chat only shows these endings
        raise no
    try:
        if not os.path.isfile(p) or os.path.getsize(p) > MAX_BYTES:
            raise no
        with open(p, "rb") as f:
            vet(f.read(MAX_BYTES + 1))
    except (OSError, Refused):
        raise no
    return p


def tool_result_image(path):
    """Claude Code saves an image a tool returned as ~/.claude/projects/<this project>/<session id>/tool-results/<file>.
    Returns the real path when it is exactly a plain image file there (no links, no subfolders), else None. Nothing else under ~/.claude."""
    try:
        if not isinstance(path, str) or not path or len(path) > 1000 or "\x00" in path or "\n" in path:
            return None
        proj = os.path.join(HOME, ".claude", "projects", re.sub(r"[/.]", "-", COMPUTER))     # same name rule as host.py sdir()
        p = os.path.realpath(_ex(path))
        parent, name = os.path.split(p)
        sid_dir, leaf = os.path.split(parent)
        if leaf != "tool-results" or os.path.dirname(sid_dir) != proj or not re.fullmatch(r"[0-9a-f-]{36}", os.path.basename(sid_dir)):
            return None
        if not re.search(r"\.(png|jpe?g|gif|webp)$", name, re.I) or not os.path.isfile(p) or os.path.getsize(p) > MAX_BYTES:
            return None
        with open(p, "rb") as f:
            vet(f.read(MAX_BYTES + 1))
        return p
    except (OSError, Refused):
        return None


def import_tool_result(path):
    """Copy a tool-result image into ~/computer/attachments. Returns the new path, or None."""
    p = tool_result_image(path)
    if p is None:
        return None
    with open(p, "rb") as f:
        return save(f.read(MAX_BYTES + 1), "tool")


# ---------------------------------------------------------------- web images
def public_ip(s):
    a = ipaddress.ip_address(s)
    if a.version == 6 and a.ipv4_mapped:
        a = a.ipv4_mapped
    return a.is_global and not a.is_multicast


def check_url(u):
    """(host, request target) of an https URL we may fetch, else Refused. The address is checked in resolve()."""
    if not isinstance(u, str) or len(u) > 2000 or re.search(r"[\s\x00-\x1f\x7f]", u):
        raise Refused("bad url")
    s = urllib.parse.urlsplit(u)
    try:
        port = s.port
    except ValueError:
        raise Refused("bad url")
    if s.scheme != "https" or not s.hostname or "@" in s.netloc or port not in (None, 443):
        raise Refused("only plain https urls are allowed")
    try:
        host = s.hostname.encode("idna").decode()
    except UnicodeError:
        raise Refused("bad host")
    return host, (s.path or "/") + ("?" + s.query if s.query else "")


def resolve(host):
    """The public addresses of the host. Every address it resolves to must be public (a mixed answer is a rebinding trick)."""
    try:
        ips = list({i[4][0] for i in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
    except (socket.gaierror, UnicodeError):
        raise Refused("host not found")
    if not ips or not all(public_ip(i.split("%")[0]) for i in ips):
        raise Refused("that address is not public")
    return sorted(ips, key=lambda i: ":" in i)       # IPv4 first: many machines have no IPv6 route


class _Pinned(http.client.HTTPSConnection):
    """Connects to the address we checked (not a second DNS lookup), and still verifies the certificate for the host name."""
    def __init__(self, host, ip, timeout):
        super().__init__(host, 443, timeout=timeout, context=ssl.create_default_context())
        self.ip = ip

    def connect(self):
        err = OSError("no address")
        for ip in ([self.ip] if isinstance(self.ip, str) else self.ip):      # only addresses resolve() approved
            try:
                s = socket.create_connection((ip, 443), self.timeout)
                self.sock = self._context.wrap_socket(s, server_hostname=self.host)
                return
            except OSError as e:
                err = e
        raise err


def request(host, ip, target, deadline):
    """One GET. Returns (status, location, body up to MAX_BYTES + 1). Test seam."""
    c = _Pinned(host, ip, max(1, min(8, deadline - time.time())))
    try:
        c.request("GET", target, headers={"Host": host, "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) lcars-computer",
                                           "Accept": "image/png,image/jpeg,image/gif,image/webp", "Accept-Encoding": "identity"})
        r = c.getresponse()
        loc = r.getheader("Location") or ""
        if r.status != 200:
            return r.status, loc, b""
        body = b""
        while len(body) <= MAX_BYTES:
            if time.time() > deadline:
                raise Refused("download took too long")
            chunk = r.read(65536)
            if not chunk:
                break
            body += chunk
        return 200, loc, body
    except (OSError, http.client.HTTPException):
        raise Refused("download failed")
    finally:
        c.close()


def fetch(url, secs=20):
    """Bytes of a real raster image behind an https URL. Up to 3 redirects, each one fully re-checked."""
    deadline = time.time() + secs
    for _ in range(4):
        host, target = check_url(url)
        status, loc, body = request(host, resolve(host), target, deadline)
        if status in (301, 302, 303, 307, 308) and loc:
            url = urllib.parse.urljoin("https://%s%s" % (host, target), loc)
            continue
        if status != 200:
            raise Refused("the server said %d" % status)
        vet(body)
        return body
    raise Refused("too many redirects")


def save(data, prefix="web", ext=None):
    """Write checked image bytes into ~/computer/attachments under a name we make up. Returns the path."""
    k = ext or vet(data)
    os.makedirs(ATTACH, mode=0o700, exist_ok=True)
    p = os.path.join(ATTACH, "%s-%d-%s.%s" % (prefix, int(time.time() * 1000), secrets.token_hex(3), EXT[k]))
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    return p
