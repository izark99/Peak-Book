load('config.js');
var CATEGORIES = [[4, "Lãng mạn"], [6, "Fanfiction"], [3, "Kỳ ảo"], [1, "Teen Fiction"], [8, "Bí ẩn / Giật gân"],
    [9, "Kinh dị"], [12, "Siêu nhiên"], [11, "Phiêu lưu"], [16, "Hành động"], [5, "Khoa học viễn tưởng"],
    [23, "Lịch sử"], [7, "Hài hước"], [21, "Tiểu thuyết chung"], [18, "Truyện ngắn"], [2, "Thơ"],
    [19, "Ma cà rồng"], [22, "Người sói"], [17, "Phi hư cấu"]];
function execute() {
    var data = [];
    for (var i = 0; i < CATEGORIES.length; i++)
        data.push({ title: CATEGORIES[i][1], input: listUrl("hot", CATEGORIES[i][0], LANG), script: "gen.js" });
    return Response.success(data);
}
