async function execute(url) {
  var html = await (await fetch(url)).text();
  return Html.select(html, '#toc a').map(function (a) {
    return { name: a.text, url: absUrl(url, a.attr('href')) };
  });
}
