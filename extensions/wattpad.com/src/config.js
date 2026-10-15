// Viết tay: Wattpad render bằng JavaScript nên extension gọi thẳng API JSON của site.
var BASE_URL = "https://www.wattpad.com";
var LANG = 19; // ngôn ngữ của tab Home/Thể loại: 19 = Tiếng Việt, 1 = English
var LIST_FIELDS = "stories(id,title,cover,user(name)),nextUrl";

function api(url) {
    var r = fetch(url);
    return r.ok ? r.json() : null;
}

function storyId(url) {
    var m = String(url).match(/\/story\/(\d+)/) || String(url).match(/(\d+)/);
    return m ? m[1] : "";
}

// Danh sách truyện từ API; nextUrl của Wattpad dùng làm trang sau.
function storyList(url) {
    var j = api(url);
    if (!j) return Response.error("Không tải được: " + url);
    var data = [];
    for (var i = 0; i < j.stories.length; i++) {
        var s = j.stories[i];
        data.push({ name: s.title, link: BASE_URL + "/story/" + s.id, cover: s.cover, description: s.user ? s.user.name : "", host: BASE_URL });
    }
    return Response.success(data, data.length && j.nextUrl ? j.nextUrl : null);
}

function listUrl(filter, category, lang) {
    return BASE_URL + "/api/v3/stories?filter=" + filter + (category ? "&category=" + category : "") +
        (lang ? "&language=" + lang : "") + "&limit=20&fields=" + LIST_FIELDS;
}
