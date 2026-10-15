load('config.js'); load('lib.js');
function execute(url) {
    var page = fixHost(url), data = [], seen = {}, visited = {};
    if (TOC_LINK) { // full chapter list lives on another page
        var d = getDoc(page), a = d ? d.select(TOC_LINK).first() : null;
        if (a) page = abs(a.attr("href"), page);
    }
    for (var n = 0; page && !visited[page] && n < TOC_MAX_PAGES; n++) {
        visited[page] = 1;
        var doc = getDoc(page);
        if (!doc) break;
        var els = TOC ? doc.select(TOC) : doc.select("a[href]"), added = 0;
        for (var i = 0; i < els.size(); i++) {
            var e = els.get(i), link = abs(e.attr("href"), page), name = label(e);
            if (!link || seen[link] || (!TOC && !CHAPTER_RE.test(name))) continue;
            seen[link] = 1; added++;
            data.push({ name: name, url: link, host: BASE_URL });
        }
        if (!added) break; // a "next" link that brings no new chapters = end of list
        page = nextUrl(doc, page);
    }
    if (TOC_REVERSE) data.reverse();
    return Response.success(data);
}
