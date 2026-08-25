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

// Which characters of `text` a query landed on, mirroring score(): a
// contiguous run for exact / prefix / substring, one index per query
// character for a subsequence, [] for no match.
function matchIndices(text, q) {
    var t = String(text).toLowerCase(), out = [];
    if (!q) return out;
    var i = t.indexOf(q);
    if (i >= 0) {
        for (var k = 0; k < q.length; k++) out.push(i + k);
        return out;
    }
    var qi = 0;
    for (var ti = 0; ti < t.length && qi < q.length; ti++)
        if (t[ti] === q[qi]) { out.push(ti); qi++; }
    return qi === q.length ? out : [];
}

function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Label indices the query landed on. The leaf is tried first, like pathScore
// ranks it: on "p", "power/power off" would otherwise light up the parent's p
// and leave the leaf — the part that actually won the row — plain.
function labelHits(label, q) {
    var leafAt = String(label).lastIndexOf("/") + 1;
    var hits = matchIndices(String(label).slice(leafAt), q).map(function (i) { return i + leafAt; });
    return hits.length ? hits : matchIndices(label, q);
}

// "power/profile/balanced" → "power / profile / balanced", what the row shows.
function displayText(label) {
    return String(label).split("/").join(" / ");
}

// Rich-text breadcrumb: path segments dim, the leaf in the row colour, and
// any character under a swipe in `bright` whichever segment it is in — dim
// text on the marker was unreadable. The swipes themselves are not in here:
// Qt's rich text draws a background as a flat brush with no radius, so they
// are rectangles behind the text, placed from markRuns() by advance widths.
function highlight(label, q, dim, bright) {
    var hits = labelHits(label, q), hit = {};
    for (var i = 0; i < hits.length; i++) hit[hits[i]] = true;
    var segs = String(label).split("/"), out = "", pos = 0;
    for (var si = 0; si < segs.length; si++) {
        var seg = segs[si], isLeaf = si === segs.length - 1, run = "";
        for (var ci = 0; ci < seg.length; ci++, pos++) {
            var ch = esc(seg[ci]);
            run += hit[pos] ? '<font color="' + bright + '">' + ch + "</font>" : ch;
        }
        out += isLeaf ? run : '<font color="' + dim + '">' + run + " / </font>";
        pos++; // the "/"
    }
    return out;
}

// Highlighter runs as [start, length] in displayText() coordinates — the
// text the row shows, where every "/" has become " / ". Adjacent hits merge,
// so a substring is one swipe and a subsequence several.
function markRuns(label, q) {
    var hits = labelHits(label, q), runs = [], segs = String(label).split("/");
    // label index → display index: each "/" crossed adds 2 (the spaces)
    var shift = [], acc = 0;
    for (var si = 0, pos = 0; si < segs.length; si++) {
        for (var ci = 0; ci < segs[si].length; ci++, pos++) shift[pos] = acc;
        pos++; acc += 2;
    }
    for (var i = 0; i < hits.length; i++) {
        var d = hits[i] + shift[hits[i]];
        var last = runs[runs.length - 1];
        if (last && last[0] + last[1] === d) last[1]++;
        else runs.push([d, 1]);
    }
    return runs;
}

// Spotlight-style calculator. Returns the value of an arithmetic expression,
// or null when the text is not one — a query that is not an expression must
// fall through to the menu search untouched, so "power" and "2fa" are null,
// not errors. No eval(): a query is typed input, and a JS evaluator would
// happily run whatever else got pasted into it.
//
// Grammar: numbers (decimals, 1e3), + - * / % ^, parentheses, unary minus.
// Precedence climbing; ^ is right-associative.
function calc(src) {
    var s = String(src).replace(/\s+/g, "");
    if (s === "" || !/^[0-9.eE+\-*/%^()]+$/.test(s) || !/[0-9]/.test(s) || !/[+\-*/%^]/.test(s.slice(1)))
        return null;
    var pos = 0, ok = true;
    function peek() { return s[pos]; }
    function number() {
        var m = /^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/.exec(s.slice(pos));
        if (!m) { ok = false; return 0; }
        pos += m[0].length;
        return parseFloat(m[0]);
    }
    function primary() {
        var c = peek();
        if (c === "(") { pos++; var v = expr(0); if (peek() !== ")") { ok = false; return 0; } pos++; return v; }
        if (c === "-") { pos++; return -primary(); }
        if (c === "+") { pos++; return primary(); }
        return number();
    }
    var prec = { "+": 1, "-": 1, "*": 2, "/": 2, "%": 2, "^": 3 };
    function expr(min) {
        var lhs = primary();
        while (ok) {
            var op = peek();
            if (!(op in prec) || prec[op] < min) break;
            pos++;
            var rhs = expr(op === "^" ? prec[op] : prec[op] + 1);
            if (op === "+") lhs += rhs;
            else if (op === "-") lhs -= rhs;
            else if (op === "*") lhs *= rhs;
            else if (op === "/") lhs /= rhs;
            else if (op === "%") lhs %= rhs;
            else lhs = Math.pow(lhs, rhs);
        }
        return lhs;
    }
    var v = expr(0);
    if (!ok || pos !== s.length || !isFinite(v)) return null;
    // 0.1+0.2 → 0.3, not 0.30000000000000004; 12 significant digits is
    // past anything a menu row would be trusted for
    return parseFloat(v.toPrecision(12));
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

    assert.deepStrictEqual(matchIndices("firefox", "fox"), [4, 5, 6], "substring run");
    assert.deepStrictEqual(matchIndices("firefox", "frfx"), [0, 2, 4, 6], "subsequence picks");
    assert.deepStrictEqual(matchIndices("firefox", "zzz"), [], "no match, no indices");
    assert.strictEqual(highlight("power/profile/balanced", "", "D", "B"),
        '<font color="D">power / </font><font color="D">profile / </font>balanced', "breadcrumb");
    assert.strictEqual(highlight("power/suspend", "po", "D", "B"),
        '<font color="D"><font color="B">p</font><font color="B">o</font>wer / </font>suspend',
        "marked characters go bright even inside a dim parent");
    assert.ok(highlight("a<b", "", "D", "B").indexOf("&lt;") >= 0, "html escaped");
    assert.strictEqual(displayText("power/profile/balanced"), "power / profile / balanced", "display text");
    assert.deepStrictEqual(markRuns("apps/Firefox", "fox"), [[11, 3]], "substring: one run, shifted past ' / '");
    assert.deepStrictEqual(markRuns("apps/Firefox", "frfx"), [[7, 1], [9, 1], [11, 1], [13, 1]], "subsequence: several runs");
    assert.deepStrictEqual(markRuns("power/power off", "p"), [[8, 1]], "leaf match wins over parent match");
    assert.deepStrictEqual(markRuns("power/suspend", "pow"), [[0, 3]], "parent-only match still marked");
    assert.deepStrictEqual(markRuns("firefox", "zzz"), [], "no match, no runs");

    assert.strictEqual(calc("2*(3+4)"), 14, "parens and precedence");
    assert.strictEqual(calc("2^3^2"), 512, "^ is right-associative");
    assert.strictEqual(calc("-2^2"), 4, "unary minus binds tighter than ^ (as typed, -2 squared)");
    assert.strictEqual(calc("10/4"), 2.5, "division is real");
    assert.strictEqual(calc("0.1+0.2"), 0.3, "float noise trimmed");
    assert.strictEqual(calc("7 % 3"), 1, "modulo, whitespace ignored");
    assert.strictEqual(calc("1e3*2"), 2000, "exponent notation");
    assert.strictEqual(calc("power"), null, "words are not expressions");
    assert.strictEqual(calc("2fa"), null, "letters after a digit are not an expression");
    assert.strictEqual(calc("42"), null, "a bare number is a search, not a sum");
    assert.strictEqual(calc("2+"), null, "dangling operator");
    assert.strictEqual(calc("(2+3"), null, "unbalanced paren");
    assert.strictEqual(calc("1/0"), null, "infinity is not an answer");

    console.log("MenuModel: all checks passed");
}
