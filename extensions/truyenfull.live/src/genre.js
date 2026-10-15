load('config.js'); load('lib.js');
function execute() {
    var data = [];
    for (var i = 0; i < GENRES.length; i++) data.push({ title: GENRES[i][0], input: abs(GENRES[i][1]), script: "gen.js" });
    return Response.success(data);
}
