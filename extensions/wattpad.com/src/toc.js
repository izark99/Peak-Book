load('config.js');
function execute(url) {
    var s = api(BASE_URL + "/api/v3/stories/" + storyId(url) + "?fields=parts(id,title,url)");
    if (!s) return Response.error("Không tải được mục lục: " + url);
    var data = [];
    for (var i = 0; i < s.parts.length; i++) data.push({ name: s.parts[i].title, url: s.parts[i].url, host: BASE_URL });
    return Response.success(data);
}
