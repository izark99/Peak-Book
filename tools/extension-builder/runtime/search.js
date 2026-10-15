load('config.js'); load('lib.js');
function execute(key, page) { return listPage(abs(SEARCH.replace("{key}", encodeURIComponent(key))), page); }
