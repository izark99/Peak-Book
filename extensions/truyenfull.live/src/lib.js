// Shared helpers for every generated extension. Selectors live in config.js.
// ES5 only: Vbook runs scripts on Rhino.
var CHAPTER_RE = /((ch(ư|u)(ơ|o)ng|chapter|chap|ch\.|h(ồ|o)i|quy(ể|e)n|t(ậ|a)p|episode|ep\.?)\s*[:.#]?\s*\d+|第\s*[\d一二三四五六七八九十百千零]+\s*[章回节話话])/i;
var NEXT_RE = /^(next|next page|next ?[›»>]+|tiếp|tiếp theo|trang (sau|tiếp|kế)|sau|›|»|>|>>|下一页|下页)$/i;
var TOC_MAX_PAGES = 500;
var JUNK = "a, script, style, iframe, ins, noscript, form, button, .ads, .adsbygoogle, [id^=ads], [class^=ads], [class^=ad-], [id^=ad-]";

// Link label: the title attribute is often the clean version of a cluttered text.
function label(a) {
    var t = str(a.text()), ti = str(a.attr("title"));
    return ti && (!t || ti.length < t.length) ? ti : t;
}

function str(x) { return x == null ? "" : String(x).replace(/^\s+|\s+$/g, ""); }

function abs(u, base) {
    u = str(u);
    if (!u || /^(javascript|#|data:|mailto:)/i.test(u)) return "";
    if (/^https?:\/\//i.test(u)) return u;
    if (u.indexOf("//") === 0) return "https:" + u;
    var m = str(base || BASE_URL).match(/^(https?:\/\/[^\/]+)([^?#]*)/);
    if (u.charAt(0) === "/") return m[1] + u;
    if (u.charAt(0) === "?") return m[1] + m[2] + u;
    return m[1] + (m[2] || "/").replace(/[^\/]*$/, "") + u;
}

// Sites rotate domains; always talk to the current BASE_URL.
function fixHost(url) { return str(url).replace(/^https?:\/\/[^\/]+/, BASE_URL); }

function getDoc(url) {
    var r = fetch(url, { headers: HEADERS });
    if (!r.ok) return null;
    return CHARSET ? r.html(CHARSET) : r.html();
}

function val(e, attr) {
    if (!e) return "";
    if (attr === "text") return str(e.text());
    if (attr === "html") return str(e.html());
    if (attr === "img") return img(e);
    return str(e.attr(attr));
}

// specs: [[selector, attr], ...] -> first non-empty value.
function pick(doc, specs) {
    for (var i = 0; i < specs.length; i++) {
        var v = val(doc.select(specs[i][0]).first(), specs[i][1]);
        if (v) return v;
    }
    return "";
}

function img(e) {
    if (!e) return "";
    if (str(e.tagName()).toLowerCase() !== "img") {
        var i = e.select("img, [data-src], [data-original], [data-image], [data-bg]").first();
        if (!i) {
            var m = str(e.attr("style")).match(/url\(['"]?([^'")]+)/);
            return m ? abs(m[1]) : "";
        }
        e = i;
    }
    var attrs = ["data-src", "data-original", "data-lazy-src", "data-lazy", "lazy-src", "data-cfsrc", "data-image", "data-bg", "src"];
    for (var k = 0; k < attrs.length; k++) {
        var v = str(e.attr(attrs[k]));
        if (v && v.indexOf("data:") !== 0) return abs(v);
    }
    return "";
}

// Generic "next page" finder: rel=next, then next-ish text, then active page number + 1.
function nextUrl(doc, cur) {
    var e = doc.select("a[rel=next], link[rel=next]").first();
    if (e && abs(e.attr("href"), cur)) return abs(e.attr("href"), cur);
    var as = doc.select("a[href]");
    for (var i = 0; i < as.size(); i++) {
        var a = as.get(i);
        if (NEXT_RE.test(str(a.text())) || NEXT_RE.test(str(a.attr("title"))) || /next/i.test(str(a.attr("aria-label"))))
            return abs(a.attr("href"), cur);
    }
    var act = doc.select("[class*=pag] .active, [class*=pag] .current, [class*=pag] [aria-current]").first();
    var n = act ? parseInt(str(act.text()), 10) : NaN;
    if (!isNaN(n)) {
        var ps = doc.select("[class*=pag] a[href]");
        for (var j = 0; j < ps.size(); j++)
            if (str(ps.get(j).text()) === String(n + 1)) return abs(ps.get(j).attr("href"), cur);
    }
    return "";
}

// Story list (home tabs, genres, search). Tries detected layouts, then any link that looks like a story.
function parseList(doc, base) {
    var data = [], seen = {};
    function add(a, item) {
        var link = abs(a.attr("href"), base);
        if (!link || seen[link]) return;
        var name = label(a) || str(item.select("img").attr("alt"));
        if (!name) return;
        seen[link] = 1;
        data.push({ name: name, link: link, cover: img(item), description: "", host: BASE_URL });
    }
    for (var s = 0; s < LIST.length && !data.length; s++) {
        var items = doc.select(LIST[s].item);
        for (var i = 0; i < items.size(); i++) {
            var it = items.get(i);
            var a = LIST[s].link ? it.select(LIST[s].link).first() : it;
            if (a) add(a, it);
        }
    }
    if (!data.length) {
        var as = doc.select("a[href]");
        for (var j = 0; j < as.size(); j++)
            if (STORY_RE.test(abs(as.get(j).attr("href"), base)) && abs(as.get(j).attr("href"), base).indexOf(BASE_URL) === 0)
                add(as.get(j), as.get(j).parent());
    }
    return data;
}

function listPage(url, page) {
    url = page ? str(page) : url;
    var doc = getDoc(url);
    if (!doc) return Response.error("Không tải được: " + url);
    var next = nextUrl(doc, url);
    return Response.success(parseList(doc, url), next && next !== url ? next : null);
}
