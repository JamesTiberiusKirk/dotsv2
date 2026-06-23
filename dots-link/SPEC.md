# dots-link

A dotfiles symlink manager for this repo, rewritten in Go. It links files from
the repo into `$HOME` per a per-host manifest, and keeps the live filesystem
converged to that manifest — including safely pulling and applying remote
changes without leaving broken symlinks behind.

---

## Model

- **Repo:** `$DOTS_DIR = $HOME/.dots`
- **Manifest:** `hosts/<hostname>` — one entry per line, `#` comments and blank
  lines ignored. Each entry is a path relative to **both** the repo and `$HOME`
  (same suffix), e.g. `.config/hypr`, `.scripts/imports`.
- **Desired state** is the manifest. `sync` converges the filesystem to it; for
  remote updates the desired state is the **remote** manifest (`origin/<branch>`).
- The filesystem is the source of truth for *what is linked* — never a recorded
  ref or state file. Reconciliation is idempotent: re-running always converges,
  partial failures self-heal on the next run.

---

## Layout & build

- Go module lives in `dots-link/` (non-dot dir so it isn't itself a managed dotfile).
- **Cobra** for commands, **Bubble Tea** + **lipgloss** for confirm UIs.
- `make install` → `go install ./dots-link` → binary lands in `~/go/bin/dots-link`
  (on `PATH`). The tool is therefore **not** a managed symlink: the old
  `.scripts/dots-link` bash script is removed from the repo and dropped from all
  host manifests.

### Code structure (testable seams)

Pure functions (string/ref in, struct out) — unit-tested in isolation:
- `resolvePath(input) -> entry`
- manifest parse / serialize (comment-preserving)
- plan computation (current FS state + target manifest -> list of actions)

Side effects pushed to the edges — git, filesystem, Bubble Tea TUI.

Rough files: `main.go` (dispatch), `manifest.go`, `paths.go`, `link.go`
(remove/status), `archive.go`, `sync.go`, `gitdiff.go`, `tui.go`, `*_test.go`.

### Correctness invariants

- Always `Lstat`/`Readlink`, **never** `Stat`. After `archive` (or a remote
  removal) other hosts hold *dangling* symlinks; `Stat` follows the link and
  errors on dangling ones, so it would miss exactly the links that must be pruned.
- Unlink removes the **symlink only** — never recurses into or deletes repo
  content or a linked directory's contents.

---

## Commands

`remove` · `status` · `archive` · `sync`

(`apply` and `diff` from the bash version are gone: `sync` subsumes `apply`
— first run on a fresh host is all-links/no-unlinks — and `sync --dry-run`
subsumes `diff`.)

---

### `remove`

Tear down **all** of this host's managed symlinks (uninstall on this machine)
**without** touching the manifest.

- For each manifest entry: if `$HOME/<entry>` is a symlink pointing into the repo
  → unlink. Real files, foreign symlinks, and missing entries are left alone.
- Repo files are untouched — only the live links go.

```
dots-link remove
```

---

### `status`

Read-only health of every manifest entry. No changes.

Per entry, one of:
- `ok` — correct symlink
- `not linked` — nothing there
- `conflict` — wrong symlink (shows its target) or a real file/dir in the way
- `missing src` — entry listed but no file in the repo

```
dots-link status
```

---

### `archive <path>`

Retire a config: pull it out of active management and stash it, unsymlinked,
under `archive/` in the repo. Propagates to all hosts via git.

`<path>` accepts the `$HOME` symlink, the repo file, or a relative path; it is
normalized (symlinks followed, prefix stripped) to a manifest entry. It must be
a **whole** manifest entry — a sub-path inside a managed directory is rejected.

Steps:
1. Resolve `<path>` → entry. Not in **any** host manifest → error, stop.
2. Remove that entry's line from **every** file in `hosts/`.
3. `$HOME/<entry>` is a symlink into the repo → unlink it. No symlink (or a real
   file) → skip, leave it alone.
4. Move `$DOTS/<entry>` → `archive/<entry>`. If the destination already exists →
   suffix the new one with `.<timestamp>`.

**Interactive:** shows what it is about to do (manifest lines to remove, symlink
to unlink, file move) and asks for confirmation before proceeding. `-y` bypasses.

Result: live link gone on this host, entry gone on every host, file preserved as
plain files in `archive/`. Other hosts drop their now-dangling link on their next
`sync`.

```
dots-link archive ~/.config/hypr
dots-link archive .config/hypr
dots-link archive ~/.dots/.config/hypr
```

---

### `sync`

Pull remote changes and converge the local filesystem **safely** — so you never
pull, discover files were deleted, and end up with broken symlinks.

Desired state = the **remote** manifest. `sync` diffs local FS ↔ remote, decides
the symlink consequences *before* mutating anything, gates on git-merge safety,
then applies the merge and the link/unlink fixups together.

**Flow**
1. `git fetch`
2. **Host-manifest guard:** if `hosts/<thishost>` is missing on the remote →
   refuse, exit, change nothing. (Use `remove` by hand to tear down.)
3. **Merge-safety gate:** clean fast-forward *or* clean auto-merge → proceed.
   Real conflicts (including local uncommitted edits that would conflict) → abort
   the merge, change nothing, tell the user to fix by hand.
4. **Compute plan** against `origin/<branch>` (see case matrix).
5. **Confirm:** Bubble Tea screen lists *to link* / *to unlink* / *conflicts* /
   *warnings* → `y`/`n`.
6. **Apply, in this order** (no dangling window):
   `unlink removals` → `merge` → `link additions`.
   Idempotent — if anything dies mid-way, re-running reconciles.

**Flags**
- `-y`, `--yes` — skip the TUI, apply immediately (cron/scripts)
- `--dry-run` — steps 1–4 then print the plan and exit; no merge, no changes

**Prune scope:** `sync` looks for stale links only under home-root dotfiles,
`.config/*`, and `.scripts/*`, and only ever unlinks links whose target is inside
the repo. Nothing else is at risk.

```
dots-link sync
dots-link sync --dry-run
dots-link sync -y
```

#### Case matrix — what can change on remote, and how `sync` handles it

**Manifest entry changes**

| Remote change | Handling |
|---|---|
| Entry added (file present in repo) | **link** (after merge) |
| Entry removed, file also gone (archive) | **unlink** local symlink (dangles post-merge) |
| Entry removed, file still in repo | **unlink** symlink; file stays, unmanaged |
| Entry unchanged | ensure link is correct (fixes local drift) |

**Repo file (target) changes**

| Remote change | Handling |
|---|---|
| File content edited | no link action — path unchanged, content updates on merge |
| File renamed, manifest updated | old entry removed + new added → **unlink old, link new** |
| File deleted but entry still listed | **broken** (`missing src`) → warn + show on confirm, no link, do not unlink (still managed); proceed |

**Whole-host manifest changes**

| Remote change | Handling |
|---|---|
| New `hosts/<thishost>` appears (first time) | link everything |
| `hosts/<thishost>` deleted entirely | **refuse, exit, no changes** (use `remove`) |

**Local FS / conflict cases**

| State | Handling |
|---|---|
| Symlink already correct | no-op |
| Symlink missing though entry exists | **link** (drift) |
| Dangling link into the repo | source present upstream → left (merge restores it); source gone → **removed** (never leave a dangling link) |
| Real file where a link should go | **conflict** → report; resolved by `--local`/`--remote`/`--it` |
| Foreign symlink (points outside repo) in the way | **conflict** → report; resolved by `--local`/`--remote`/`--it` |

**Git-level safety (gate before any apply)**

| Situation | Handling |
|---|---|
| Fast-forward | safe → proceed |
| Diverged, clean auto-merge | proceed |
| Diverged with conflicts | **bail**, change nothing, fix by hand |
| Local uncommitted edits that would conflict | **bail**, change nothing |
| Already up to date / local ahead | no merge; still reconcile FS drift |

**Conflict resolution** (mutually-exclusive flags on `sync`; default reports
conflicts and changes nothing):

- **`--local`** — local wins. A real file is absorbed into the repo (moved in,
  uncommitted, for review) and linked. A foreign symlink is dereferenced: its
  target's content is copied into the repo, then linked. A broken foreign link
  has nothing to adopt → falls back to the dangling rule (relink if the repo has
  the source, else remove).
- **`--remote`** — repo wins. The live file or foreign symlink is removed and
  replaced with a symlink into the repo. If the repo has no source for the entry,
  it can't link → reported as a warning instead.
- **`--it`** — interactive. Prompts per conflict: `[l]ocal / [r]emote / [s]kip`.
  Skip leaves that conflict untouched. Needs a TTY.

---

## Deferred

- `restore` / `unarchive` — pull something back out of `archive/` into management.
