async function execute(url) {
  var res = await fetch(url);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return Html.select(await res.text(), '#content')[0].html;
}
