async function execute(url) {
  var html = await (await fetch(url)).text();
  var img = Html.select(html, '.cover img')[0];
  return {
    name: Html.select(html, 'h1')[0].text,
    author: Html.select(html, '.author')[0].text,
    cover: img ? absUrl(url, img.attr('src')) : null,
    description: Html.select(html, '.desc')[0].text
  };
}
