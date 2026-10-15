load('config.js');
function execute(url) {
    var s = api(BASE_URL + "/api/v3/stories/" + storyId(url) + "?fields=title,cover,description,completed,user(name),tags,numParts,readCount,voteCount");
    if (!s) return Response.error("Không tải được truyện: " + url);
    return Response.success({
        name: s.title,
        cover: s.cover,
        author: s.user ? s.user.name : "",
        description: String(s.description || "").replace(/\n/g, "<br>"),
        detail: "Số chương: " + s.numParts + "<br>Lượt đọc: " + s.readCount + "<br>Bình chọn: " + s.voteCount +
            (s.tags && s.tags.length ? "<br>Tags: " + s.tags.join(", ") : ""),
        ongoing: !s.completed,
        host: BASE_URL
    });
}
