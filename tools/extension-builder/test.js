// Offline self-check: `node test.js`. Fixture HTML -> detectors -> runtime lib on the same HTML.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const cheerio = require('cheerio');
const D = require('./detect');
const { parseHtml } = require('./shim');

const page = (url, html) => ({ url, $: cheerio.load(html) });
const story = page('https://x.vn/ten-truyen/', `<html><head><meta property="og:title" content="Ten Truyen - X">
<meta property="og:image" content="https://x.vn/c.jpg"></head><body><nav><a href="/the-loai/a/">A</a></nav>
<div class="info"><h1 class="title">Ten Truyen</h1><img data-src="/c.jpg" src="data:,"><a href="/tac-gia/b/">Tac Gia B</a>
<span>Trạng thái: Full</span></div><div class="desc-text">${'Mo ta truyen. '.repeat(10)}</div>
<ul class="chapters">${[1, 2, 3, 4].map((i) => `<li><a href="/ten-truyen/chuong-${i}/">Chương ${i}: abc</a></li>`).join('')}</ul>
<ul class="pagination"><li class="active"><span>1</span></li><li><a href="/ten-truyen/trang-2/">2</a></li></ul></body></html>`);
const chap = page('https://x.vn/ten-truyen/chuong-1/', `<body><div class="nav"><a href="/">Home</a></div>
<div id="chapter-c"><p>${'Noi dung chuong. '.repeat(30)}</p><p>Doan hai.</p><script>ad()</script></div></body>`);
const list = page('https://x.vn/danh-sach/moi/', `<body><div class="list">${['a', 'b', 'c', 'd'].map((s) =>
  `<div class="row"><img src="/${s}.jpg"><h3><a href="/truyen-${s}/">Truyen ${s}</a></h3><a href="/truyen-${s}/chuong-9/">Chương 9</a></div>`).join('')}</div>
<a rel="next" href="?page=2">2</a></body>`);

const re = new RegExp(D.storyPattern(story.url).any);
assert(re.test('https://x.vn/truyen-a/') && !re.test('https://x.vn/truyen-a/chuong-1/'));

const toc = D.detectToc(story, re);
assert.equal(story.$(toc.sel).length, 4);
assert(!D.detectToc(list, re), 'latest-chapter links of many stories are not a TOC');
assert.equal(D.detectContent(chap).sel, 'div#chapter-c');
const l = D.detectList(list, re);
assert.equal(list.$(l.item).length, 4);
const { r } = D.detectDetail(story);
assert.equal(r.name[0][0], 'h1.title');
assert.equal(r.desc[0][0], 'div.desc-text');
assert.equal(r.info, 'div.info');

assert(!D.jsRendered(story));
assert(D.jsRendered(page('https://app.x/', `<body><div id="root"></div><script>window.data=${JSON.stringify('x'.repeat(500))}</script></body>`)));

// Runtime helpers on the detected config, through the Jsoup emulation.
const ctx = vm.createContext({ BASE_URL: 'https://x.vn', LIST: [l], STORY_RE: re });
vm.runInContext(fs.readFileSync(path.join(__dirname, 'runtime/lib.js'), 'utf8'), ctx);
const items = ctx.parseList(parseHtml(list.$.html()), list.url);
assert.deepEqual(items.map((i) => i.name), ['Truyen a', 'Truyen b', 'Truyen c', 'Truyen d']);
assert.equal(items[0].cover, 'https://x.vn/a.jpg');
assert.equal(ctx.nextUrl(parseHtml(list.$.html()), list.url), 'https://x.vn/danh-sach/moi/?page=2');
assert.equal(ctx.nextUrl(parseHtml(story.$.html()), story.url), 'https://x.vn/ten-truyen/trang-2/');
assert.equal(ctx.img(parseHtml(story.$.html()).select('img').first()), 'https://x.vn/c.jpg');
// plugin.zip: first entry round-trips through the local header.
const os = require('os');
const zlib = require('zlib');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ext-'));
fs.writeFileSync(path.join(tmp, 'plugin.json'), '{"a":"Truyện"}');
const zip = fs.readFileSync(require('./pack').pack(tmp));
const nameLen = zip.readUInt16LE(26), size = zip.readUInt32LE(18);
assert.equal(zip.toString('utf8', 30, 30 + nameLen), 'plugin.json');
assert.equal(zlib.inflateRawSync(zip.subarray(30 + nameLen, 30 + nameLen + size)).toString(), '{"a":"Truyện"}');
fs.rmSync(tmp, { recursive: true });
console.log('ok');
