load('config.js'); load('lib.js');
function execute(url) {
    url = fixHost(url);
    var doc = getDoc(url);
    if (!doc) return Response.error("Không tải được: " + url);
    var info = INFO ? doc.select(INFO).first() : null;
    var infoText = info ? str(info.text()) : "";
    return Response.success({
        name: pick(doc, NAME),
        cover: abs(pick(doc, COVER), url),
        author: pick(doc, AUTHOR).replace(/^(tác giả|author|作\s*者)\s*[:：]?\s*/i, ""),
        description: pick(doc, DESC),
        detail: info ? str(info.html()) : "",
        ongoing: !/(hoàn thành|hoàn tất|đã hoàn|full\b|completed|finished|完结|完本|已完成)/i.test(infoText),
        host: BASE_URL
    });
}
