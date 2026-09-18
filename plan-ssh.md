# ssh over tailscale only

Goal: sshd reachable on the tailnet IP only, keys-only, no root, on all three
Artix/runit hosts (binstar, dellstar, deathstar).

## Why a repo-owned sv instead of openssh-runit + sshd_config.d

- Per-host tailnet IP: resolved at runtime in the run script, so one file
  covers every host instead of three hardcoded config drop-ins.
- Boot race: `ListenAddress <tailnet ip>` fails to bind before tailscale0 has
  its address. The run script waits for the IP, so no crash-loop.
- `system/etc/runit/sv` is already a `dots-link/system.go` mapping with
  `enable: true`. No new mapping, no `/etc/ssh` plumbing, no extra package.
- Host keys: none of these boxes have `/etc/ssh/ssh_host_*`. Run script does
  `ssh-keygen -A` before exec.

## Files

1. `system/etc/runit/sv/sshd/run` (new)
   - `ssh-keygen -A`
   - loop until `tailscale ip -4` returns an address
   - `exec /usr/bin/sshd -D -e -o ListenAddress=$ip -o AddressFamily=inet
      -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no
      -o PermitRootLogin=no`
   - `-o` on the command line is parsed before sshd_config, and sshd is
     first-value-wins, so these beat the Artix drop-ins.
2. `system/etc/runit/sv/sshd/log/run` (new) — svlogd to /var/log/sshd,
   same shape as the tailscale sv.
3. `hosts/binstar` — add `system/etc/runit/sv/sshd`
4. `hosts/dellstar` — same
5. `hosts/deathstar` — same

No install.sh change: dots-link's sv mapping links it into
`/etc/runit/runsvdir/default` itself.

6. `install.sh` — authorized_keys block, next to the other ssh/dns bits:
   fetch `https://github.com/JamesTiberiusKirk.keys` into
   `~/.ssh/authorized_keys` (dir 0700, file 0600). On curl failure leave the
   existing file alone — never truncate, that would lock the host out.
   Source of truth stays GitHub; revoking a key there removes access on the
   next converge. Blast radius: anyone who can add a key to that GitHub
   account gets shell on all three hosts.

## Out of scope / manual

- Firewall: not needed. Naming any ListenAddress drops the 0.0.0.0 wildcard.

## Check

After a reboot (not just `sv restart sshd` — that skips the boot path):

    ss -lntp | grep sshd    # must show 100.x.y.z:22, and no 0.0.0.0:22 / *:22
    sv status sshd

Then `ssh binstar` from another tailnet node, and `ssh <lan-ip>` must hang/refuse.
