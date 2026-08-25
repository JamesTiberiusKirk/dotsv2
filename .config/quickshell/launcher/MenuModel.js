// Menu ranking. Plain JS so `node MenuModel.js` runs the self-check at the
// bottom — the QML that imports this and the check exercise the same code.

// Lower is better, -1 for no match. Exact beats prefix beats substring beats
// subsequence, so "hib" puts "hibernate" above a row that merely contains
// those letters scattered across it.
function score(text, q) {
    var t = String(text).toLowerCase();
    if (t === q) return 0;
    var i = t.indexOf(q);
    if (i === 0) return 10;
    if (i > 0) return 30;
    var qi = 0;
    for (var ti = 0; ti < t.length && qi < q.length; ti++)
        if (t[ti] === q[qi]) qi++;
    return qi === q.length ? 60 : -1;
}

// Best of the full path and its last segment: "power/hibernate" should rank on
// "hibernate" too, not only on the whole path. A match that only lands on the
// parent is penalised, otherwise typing "power" ties every row under power/ and
// the order falls to label length — surfacing "reboot" above "power off".
function pathScore(path, q) {
    var leaf = path.slice(path.lastIndexOf("/") + 1);
    var onLeaf = score(leaf, q), onPath = score(path, q);
    if (onPath >= 0) onPath += 5;
    if (onLeaf < 0) return onPath;
    if (onPath < 0) return onLeaf;
    return Math.min(onLeaf, onPath);
}

// Ties break on the shorter label, so an exact-ish short row wins over a long
// path that happens to score the same.
function ranked(rows, q) {
    return rows.map(function (r) { return { r: r, s: pathScore(r.label, q) }; })
        .filter(function (x) { return x.s >= 0; })
        .sort(function (x, y) { return x.s - y.s || x.r.label.length - y.r.label.length; })
        .map(function (x) { return x.r; });
}

if (typeof module !== "undefined" && require.main === module) {
    var assert = require("assert");
    var rows = ["power/hibernate", "power/suspend", "power/reboot", "power/power off",
                "display/sub screen ✓", "display/brightness lock ✓", "scripts/next-wallpaper",
                "apps/Firefox", "apps/Files"].map(function (p) { return { label: p }; });
    var names = function (q) { return ranked(rows, q).map(function (r) { return r.label; }); };

    assert.strictEqual(names("hib")[0], "power/hibernate", "prefix-of-leaf ranks first");
    assert.strictEqual(names("hibernate")[0], "power/hibernate", "exact leaf ranks first");
    assert.strictEqual(names("firefox")[0], "apps/Firefox", "apps are searchable from the root");
    assert.strictEqual(names("frfx")[0], "apps/Firefox", "subsequence matches");
    assert.deepStrictEqual(names("zzz"), [], "no match is empty, not everything");
    assert.ok(names("power").indexOf("power/power off") === 0, "leaf match beats parent-only match");
    // substring must outrank subsequence: "reboot" contains "boo", Firefox does not
    assert.ok(score("reboot", "boo") < score("firefox", "frfx"), "substring outranks subsequence");
    assert.strictEqual(score("suspend", "xyz"), -1, "no match is -1");

    console.log("MenuModel: all checks passed");
}
