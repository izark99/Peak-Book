load('config.js');
function execute() {
    return Response.success([
        { title: "Hot", input: listUrl("hot", 0, LANG), script: "gen.js" },
        { title: "Mới", input: listUrl("new", 0, LANG), script: "gen.js" },
        { title: "Hot (English)", input: listUrl("hot", 0, 1), script: "gen.js" }
    ]);
}
