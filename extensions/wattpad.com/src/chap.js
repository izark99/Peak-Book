load('config.js');
function execute(url) {
    // Link chương dạng https://www.wattpad.com/<partId>-<slug>
    var m = String(url).match(/wattpad\.com\/(\d+)/);
    if (!m) return Response.error("Link chương không hợp lệ: " + url);
    var r = fetch(BASE_URL + "/apiv2/storytext?id=" + m[1]);
    if (!r.ok) return Response.error("Không tải được chương (có thể là chương trả phí)");
    return Response.success(r.text());
}
