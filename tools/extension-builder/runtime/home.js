load('config.js'); load('lib.js');
function execute() {
    var tabs = [];
    for (var i = 0; i < HOME.length; i++) tabs.push({ title: HOME[i][0], input: abs(HOME[i][1]), script: "gen.js" });
    return Response.success(tabs);
}
