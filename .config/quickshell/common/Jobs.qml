pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Housekeeping cron jobs. Definitions are /etc/cron.{hourly,weekly}/job-<name>;
// /usr/local/bin/job writes <name>.status and <name>.log into /var/lib/jobs.
// One sh process reads all of it per poll. Override for testing: JOBS_DIR (status dir).
Singleton {
    id: root

    property var jobs: []           // [{ name, sched, status, last, next, log, desc, path }]
    readonly property int count: jobs.length
    readonly property int failed: jobs.filter(j => j.status === "failed").length
    readonly property int running: jobs.filter(j => j.status === "running").length
    property real nowMs: Date.now()

    readonly property string dir: Quickshell.env("JOBS_DIR") || "/var/lib/jobs"
    readonly property string cron: "/etc"

    // J<tab>name sched started ended exit running desc (desc last: may hold anything but a newline), L<tab>name<tab>line
    readonly property string script: `
d=$1; c=$2
rd() {
  started=; pid=; ended=; code=
  [ -r "$d/$n.status" ] || return 0
  while IFS== read -r k v; do
    case $k in started) started=$v;; pid) pid=$v;; ended) ended=$v;; exit) code=$v;; esac
  done < "$d/$n.status"
}
for f in "$c"/cron.hourly/job-* "$c"/cron.weekly/job-*; do
  [ -e "$f" ] || continue
  n=\${f##*/job-}; s=\${f%/*}; s=\${s##*cron.}
  rd
  desc=$(sed -n 's/^# desc: //p' "$f" | head -n 1 | tr -d '\\r')
  r=0
  if [ -z "$ended" ] && [ -n "$pid" ]; then
    # alive only if the pid is still the job wrapper (pids get reused after a reboot);
    # gone: re-read once, the job may have finished between the read and the check
    if grep -qa /usr/local/bin/job "/proc/$pid/cmdline" 2>/dev/null; then r=1; else rd; fi
  fi
  printf 'J\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$n" "$s" "$started" "$ended" "$code" "$r" "$desc"
  [ -r "$d/$n.log" ] && tail -n 8 "$d/$n.log" | tr -d '\\r' | while IFS= read -r l; do printf 'L\\t%s\\t%s\\n' "$n" "$l"; done
done
`

    Process {
        id: reader
        command: ["sh", "-c", root.script, "sh", root.dir, root.cron]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    function refresh() { if (!reader.running) reader.running = true; }

    // 30s, 2s while anything runs
    Timer {
        interval: root.running > 0 ? 2000 : 30000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function parse(text) {
        const by = {}, order = [];
        for (const line of text.split("\n")) {
            const p = line.split("\t");
            if (p[0] === "J") {
                by[p[1]] = { name: p[1], sched: p[2], started: Number(p[3]) || 0, ended: Number(p[4]) || 0,
                             code: p[5], alive: p[6] === "1", desc: p.slice(7).join("\t"), log: [] };
                order.push(p[1]);
            } else if (p[0] === "L" && by[p[1]]) {
                by[p[1]].log.push(p.slice(2).join("\t"));
            }
        }
        nowMs = Date.now();
        jobs = order.map(n => {
            const j = by[n];
            const status = !j.started ? "never"
                : j.alive ? "running"
                : (j.ended && j.code === "0") ? "ok" : "failed";
            return { name: n, sched: j.sched, status: status, last: j.ended || j.started,
                     next: nextRun(j.sched, j.started), log: j.log, code: j.code, desc: j.desc,
                     path: root.cron + "/cron." + j.sched + "/job-" + n };
        });
    }

    // hourly: next HH:01. weekly: own last start + 7 days ("~": anacron fires it when the laptop is awake);
    // never run: anacron fires it within the hour of first boot. (anacron's stamp is root 0600, unreadable.)
    function nextRun(sched, started) {
        const now = new Date();
        if (sched === "hourly") {
            const d = new Date(now);
            d.setMinutes(1, 0, 0);
            if (d <= now) d.setHours(d.getHours() + 1);
            return Qt.formatTime(d, "HH:mm");
        }
        if (!started) return "~soon";
        return "~" + Qt.formatDate(new Date(started * 1000 + 7 * 86400000), "ddd d MMM");
    }

    // "2h ago" from epoch seconds
    function ago(epoch) {
        if (!epoch) return "never";
        const s = Math.max(0, Math.floor((nowMs - epoch * 1000) / 1000));
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        if (s < 86400) return Math.floor(s / 3600) + "h ago";
        return Math.floor(s / 86400) + "d ago";
    }

    // Polkit asks for the password, so an agent has to be running (LCARS has one; the bar does not).
    function runNow(job) {
        Quickshell.execDetached(["pkexec", job.path]);
        fastPoll.n = 30;
        fastPoll.start();
    }
    // the password prompt takes a while: poll every 2s for ~60s after a click
    Timer {
        id: fastPoll
        property int n: 0
        interval: 2000; repeat: true
        onTriggered: { root.refresh(); if (--n <= 0) stop(); }
    }
}
