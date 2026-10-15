load('config.js');
function execute(key, page) {
    return storyList(page || BASE_URL + "/v4/search/stories?query=" + encodeURIComponent(key) + "&limit=20&fields=" + LIST_FIELDS);
}
