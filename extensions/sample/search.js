async function execute(query) {
  var res = await fetch(SOURCE + '/search?q=' + encodeURIComponent(query));
  var html = await res.text();
  return Html.select(html, '.book').map(function (e) {
    var a = Html.select(e.html, 'a')[0];
    var author = Html.select(e.html, '.author')[0];
    return { name: a.text, url: absUrl(res.url, a.attr('href')), author: author ? author.text : '' };
  });
}
