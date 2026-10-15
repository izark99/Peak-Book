load('config.js'); load('lib.js');
function execute(url) {
    url = fixHost(url);
    var doc = getDoc(url);
    if (!doc) return Response.error("Không tải được: " + url);
    for (var i = 0; i < CONTENT.length; i++) {
        var e = doc.select(CONTENT[i]).first();
        if (!e) continue;
        e.select(JUNK).remove();
        var html = str(e.html());
        if (html) return Response.success(html);
    }
    return Response.error("Không tìm thấy nội dung chương");
}
