#!/usr/bin/env python3
"""One-off: move project roots under ~/src, carrying Claude Code history along.

  python3 move.py            dry run: prints every step, changes nothing
  python3 move.py --run      do it (refuses while any `claude` runs)
  add --allow-busy           proceed although other processes sit in the folders

Per root: rename the folder; rename every ~/.claude/projects/<encoded> dir whose
real path (read from its transcripts) is inside it; rewrite the old path in
~/.claude.json and ~/.claude/settings.json (backups first); `git worktree
repair` repos with linked worktrees. Transcripts are left as they are.
Writes an undo log next to this script.
"""
import json, os, re, subprocess, sys, time

H = os.path.expanduser("~")
ROOTS = [
    (f"{H}/FyrmForge", f"{H}/src/ff"),
    (f"{H}/SportFreelancers", f"{H}/src/sf"),
    (f"{H}/Projects", f"{H}/src/ws"),
    (f"{H}/atom", f"{H}/src/at"),
    (f"{H}/uw", f"{H}/src/uww"),
]  # missing roots are skipped
CPROJ = f"{H}/.claude/projects"
JSON_FILES = [f"{H}/.claude.json", os.path.realpath(f"{H}/.claude/settings.json")]
REPORT_ONLY = [f"{H}/.dots"]  # dotfiles: references listed, not rewritten

RUN = "--run" in sys.argv
ALLOW_BUSY = "--allow-busy" in sys.argv


def enc(path):  # Claude Code's project dir name
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def under(path, root):
    return path == root or path.startswith(root + "/")


def remap(path):
    for old, new in ROOTS:
        if under(path, old):
            return new + path[len(old):]
    return None


def path_re(old):  # old path at a segment boundary (not /ProjectsX)
    return re.compile(re.escape(old) + r"(?![A-Za-z0-9._-])")


def claude_dir_path(d):
    """The real path a ~/.claude/projects dir belongs to: a transcript cwd
    that encodes to its name (names are ambiguous: x-y vs x/y vs x.y)."""
    full = os.path.join(CPROJ, d)
    seen = set()
    for f in sorted(os.listdir(full)):
        if not f.endswith(".jsonl"):
            continue
        with open(os.path.join(full, f), errors="replace") as fh:
            for i, line in enumerate(fh):
                if i > 200:
                    break
                for m in re.finditer(r'"cwd":"([^"]*)"', line):
                    seen.add(m.group(1))
    for c in seen:
        if enc(c) == d:
            return c
    # memory-only dir: match against real folders under the old roots
    for old, _ in ROOTS:
        if not enc(old) in d:
            continue
        for dirpath, dirs, _ in os.walk(old):
            if dirpath.count("/") - old.count("/") >= 4:
                dirs[:] = []
                continue
            dirs[:] = [x for x in dirs if x not in (".git", "node_modules")]
            if enc(dirpath) == d:
                return dirpath
    return None


def procs_in_roots():
    busy, claude = [], []
    if not os.path.isdir("/proc"):  # macOS: no /proc; close every Claude yourself
        print("  (no /proc: process checks skipped, make sure no Claude runs)")
        return busy, claude
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            comm = open(f"/proc/{pid}/comm").read().strip()
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            continue
        try:  # versioned binaries (bg sessions, daemons) are named "2.1.322"
            exe = os.readlink(f"/proc/{pid}/exe")
        except OSError:
            exe = ""
        if comm == "claude" or "/claude/versions/" in exe:
            claude.append((pid, cwd))
        elif int(pid) != os.getpid() and comm != "gtmux" and any(under(cwd, o) for o, _ in ROOTS):
            busy.append((pid, comm, cwd))
    return busy, claude


def main():
    print("== mode:", "RUN" if RUN else "DRY RUN (nothing changes)")
    problems = []

    # 1. roots
    print("\n== folders")
    for old, new in ROOTS:
        if not os.path.isdir(old):
            print(f"  skip {old} (missing)")
            continue
        if os.path.exists(new):
            problems.append(f"target exists: {new}")
        if os.stat(old).st_dev != os.stat(H).st_dev:  # rename can't cross disks
            problems.append(f"{old} is on another filesystem")
        print(f"  {old}  ->  {new}   ({len(os.listdir(old))} entries)")

    # 2. claude project dirs
    print("\n== claude history dirs (~/.claude/projects)")
    renames = []
    for d in sorted(os.listdir(CPROJ)):
        if not any(d.startswith(enc(o)) for o, _ in ROOTS):
            continue
        p = claude_dir_path(d)
        newp = remap(p) if p else None
        if not newp:
            problems.append(f"can't tell which folder {d} belongs to")
            continue
        nd = enc(newp)
        if os.path.exists(os.path.join(CPROJ, nd)):
            problems.append(f"claude dir exists: {nd}")
        renames.append((d, nd))
        print(f"  {d}  ->  {nd}")

    # 3. json path references
    print("\n== path rewrites (backup first)")
    for f in JSON_FILES:
        if not os.path.exists(f):
            continue
        txt = open(f).read()
        n = sum(len(path_re(o).findall(txt)) for o, _ in ROOTS)
        print(f"  {f}: {n} occurrences")

    # 4. worktrees
    print("\n== git worktree repair")
    repairs = []
    for old, new in ROOTS:
        if not os.path.isdir(old):
            continue
        for repo in sorted(os.listdir(old)):
            wt = os.path.join(old, repo, ".git", "worktrees")
            if not os.path.isdir(wt):
                continue
            paths = []
            for w in os.listdir(wt):
                try:
                    g = open(os.path.join(wt, w, "gitdir")).read().strip()
                except OSError:
                    continue
                wdir = os.path.dirname(g)  # <worktree>/.git -> <worktree>
                if remap(wdir) and os.path.exists(wdir):
                    paths.append(remap(wdir))
            repairs.append((os.path.join(new, repo), paths))
            print(f"  {os.path.join(new, repo)}: {len(paths)} linked worktree(s)")

    # 5. report-only references
    print("\n== NOT rewritten, fix by hand if they matter")
    pats = "|".join(re.escape(o) for o, _ in ROOTS) + r"|~/(FyrmForge|Projects|SportFreelancers|atom|uw)(/|$)"
    for base in REPORT_ONLY:
        out = subprocess.run(["grep", "-rlsE", pats, base, "--exclude-dir=.git"], capture_output=True, text=True).stdout
        for line in out.split():
            print("  ", line)

    # 6. processes
    busy, claude = procs_in_roots()
    print("\n== processes")
    for pid, cwd in claude:
        print(f"  claude pid {pid} in {cwd}")
    for pid, comm, cwd in busy:
        print(f"  {comm} pid {pid} in {cwd}")
    if claude:
        problems.append(f"{len(claude)} claude process(es) running: close every Claude first (they rewrite ~/.claude.json)")
    if busy and not ALLOW_BUSY:
        problems.append(f"{len(busy)} other process(es) inside the folders (close them, or --allow-busy: they keep running, their paths go stale)")

    print("\n== problems")
    for p in problems:
        print("  !", p)
    if not problems:
        print("  none")
    if not RUN:
        print("\nDry run only. Real run: python3 move.py --run")
        return
    if problems:
        sys.exit("\nRefusing to run; fix the problems above.")

    # --- do it ---
    ts = time.strftime("%Y%m%d-%H%M%S")
    undo = {"roots": [], "claude": [], "backups": []}
    log = os.path.join(H, f"move-undo-{ts}.json")  # not beside the script: it moves too

    def save():
        json.dump(undo, open(log, "w"), indent=1)

    for f in JSON_FILES:
        if os.path.exists(f):
            b = f"{f}.premove-{ts}"
            open(b, "w").write(open(f).read())
            undo["backups"].append([f, b])
    save()
    os.makedirs(f"{H}/src", exist_ok=True)
    for old, new in ROOTS:
        if os.path.isdir(old):
            os.rename(old, new)
            undo["roots"].append([old, new])
            save()
            print("moved", old, "->", new)
    for d, nd in renames:
        os.rename(os.path.join(CPROJ, d), os.path.join(CPROJ, nd))
        undo["claude"].append([d, nd])
        save()
    print(f"renamed {len(renames)} claude history dirs")
    for f in JSON_FILES:
        if os.path.exists(f):
            txt = open(f).read()
            for old, new in ROOTS:
                txt = path_re(old).sub(new, txt)
            tmp = f + ".tmp"
            open(tmp, "w").write(txt)
            os.rename(tmp, f)
            print("rewrote", f)
    for repo, paths in repairs:
        r = subprocess.run(["git", "-C", repo, "worktree", "repair", *paths], capture_output=True, text=True)
        print("worktree repair", repo, "ok" if r.returncode == 0 else "FAILED: " + r.stderr.strip())
    print("\ndone. undo log:", log)


main()
