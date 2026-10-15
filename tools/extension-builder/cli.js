#!/usr/bin/env node
// Usage:
//   node cli.js <url> [--out <dir>]     create an extension from a story or home page URL
//   node cli.js test <extDir> [storyUrl] run the extension's scripts against the live site
const fs = require('fs');
const path = require('path');
const { httpGet, runScript, norm } = require('./shim');
const D = require('./detect');

const say = (...a) => console.log(...a);

function findStory(home, depth = 1, tried = new Set()) {
  // Try the biggest link groups until one leads to a page with a chapter list; go one level deeper if needed.
  const gs = D.groups(home, (u) => D.host(u) === D.host(home.url) && u.replace(/\/$/, '') !== home.url.replace(/\/$/, ''))
    .filter((g) => g.length >= 2 && !g.every((a) => D.isChapter(home.$, a)))
    .sort((a, b) => b.length - a.length).slice(0, depth ? 10 : 5);
  const lists = [];
  for (const g of gs) {
    const titles = g.filter((x) => !D.isChapter(home.$, x));
    if (!titles.length) continue;
    const a = titles.reduce((x, y) => (D.text(home.$, y).length > D.text(home.$, x).length ? y : x));
    const url = D.abs(a.attribs.href, home.url);
    if (tried.has(url)) continue;
    tried.add(url);
    say('  thử ' + url);
    const p = D.load(url);
    if (p.error) continue;
    if (D.findToc(p).toc) return url;
    lists.push(p);
  }
  for (const p of depth ? lists.slice(0, 3) : []) {
    const url = findStory(p, depth - 1, tried);
    if (url) return url;
  }
  return null;
}

function create(input, outRoot) {
  say(`▶ Đọc ${input}`);
  let first = D.load(input);
  if (first.error) throw new Error(`${input}: ${first.error}`);
  const origin = new URL(first.url).origin;
  const notes = [];

  // 1. Story (detail) page
  let storyUrl = new URL(first.url).pathname !== '/' && D.findToc(first).toc ? first.url : null;
  if (!storyUrl) {
    say('• Link không phải trang truyện, đang tìm 1 truyện mẫu...');
    const home = new URL(first.url).pathname === '/' ? first : D.load(origin + '/');
    storyUrl = home.error ? null : findStory(home);
    if (!storyUrl) throw new Error('Không tìm được trang truyện có danh sách chương. Hãy đưa link trang giới thiệu 1 truyện cụ thể.');
  }
  const story = storyUrl === first.url ? first : D.load(storyUrl);
  const pat = D.storyPattern(story.url);
  const storyRe = new RegExp(pat.any);
  say(`• Trang truyện: ${story.url}`);

  const { r: det, nameEl } = D.detectDetail(story);

  // 2. Table of contents (on the story page or on a linked "all chapters" page)
  const { toc, tocLink } = D.findToc(story, storyRe);
  if (!toc) notes.push('Không tìm thấy danh sách chương (có thể load bằng AJAX/JS). toc.js đang dùng chế độ đoán theo tên "Chương/Chapter" — cần sửa TOC trong config.js.');

  // 3. Chapter content
  let content = null;
  if (toc) {
    const ch = D.load(toc.links[toc.reverse ? toc.links.length - 1 : 0].url);
    content = ch.error ? null : D.detectContent(ch);
  }
  if (!content) notes.push('Không xác định được khung nội dung chương — chap.js dùng selector phổ biến, cần kiểm tra CONTENT.');

  // 4. Home tabs, genres, story lists
  const home = D.load(origin + '/');
  const lists = [], HOME = [], GENRES = [];
  const addList = (page) => {
    const l = !page.error && D.detectList(page, storyRe);
    if (l && !lists.some((x) => x.item === l.item && x.link === l.link)) lists.push({ item: l.item, link: l.link });
    return l;
  };
  if (!home.error) {
    const seen = new Set();
    const anchors = home.$('a[href]').toArray().map((a) => [D.text(home.$, a), D.abs(a.attribs.href, home.url)]).filter(([t, u]) => t && u && D.host(u) === D.host(origin));
    for (const [t, u] of anchors) {
      if (seen.has(u) || storyRe.test(u) || HOME.length >= 6) continue;
      if (/(mới cập nhật|truyện mới|mới nhất|truyện hot|hoàn thành|truyện full|đề cử|xem nhiều|latest|new release|popular|completed|trending|hot novel|most popular|最新|排行|完本)/i.test(t) && t.length < 40) {
        seen.add(u);
        say(`  tab "${t}" ${u}`);
        if (addList(D.load(u))) HOME.push([t, u]);
      }
    }
    if (addList(home) && !HOME.length) HOME.push(['Trang chủ', origin + '/']);
    for (const [t, u] of anchors) {
      if (!seen.has(u) && /\/(the-loai|theloai|genres?|categor(y|ies)|danh-muc|tag|sort|fenlei|class)\/[^/?#]+|\/(genre|category|the-loai)[-_][^/?#]+/i.test(u) && t.length < 40) {
        seen.add(u); GENRES.push([t, u]);
      }
    }
    if (GENRES.length) addList(D.load(GENRES[0][1]));
  }
  if (!HOME.length) notes.push('Không tìm thấy trang danh sách truyện cho tab Home.');

  // 5. Search: the site's own form first, then common URL patterns. Verified by searching a real title.
  const kw = (nameEl || '').split(/\s+/).slice(0, 3).join(' ') || 'a';
  const homeLinks = new Set(home.error ? [] : home.$('a[href]').toArray().map((a) => D.abs(a.attribs.href, home.url)));
  const cands = [];
  if (!home.error) home.$('form').each((_, f) => {
    const inp = home.$(f).find('input[type=search], input[type=text], input:not([type])').filter((_, i) => i.attribs.name)[0];
    if (!inp || (f.attribs.method || 'get').toLowerCase() !== 'get') return;
    const base = D.abs(f.attribs.action || home.url, home.url);
    const extra = home.$(f).find('input[type=hidden][name]').toArray().map((i) => `&${i.attribs.name}=${encodeURIComponent(i.attribs.value || '')}`).join('');
    cands.push(`${base}${base.includes('?') ? '&' : '?'}${inp.attribs.name}={key}${extra}`);
  });
  cands.push(...['/tim-kiem/?tukhoa={key}', '/tim-kiem?q={key}', '/search?keyword={key}', '/search?q={key}', '/?s={key}', '/search/{key}'].map((p) => origin + p));
  let SEARCH = '';
  for (const c of cands) {
    const p = D.load(c.replace('{key}', encodeURIComponent(kw)));
    if (p.error) continue;
    // A real result page links a story matching the keyword and isn't just the home page again.
    const links = p.$('a[href]').toArray().filter((a) => storyRe.test(D.abs(a.attribs.href, p.url)));
    const hit = links.some((a) => D.text(p.$, a).toLowerCase().includes(kw.toLowerCase()));
    const same = links.filter((a) => homeLinks.has(D.abs(a.attribs.href, p.url))).length / (links.length || 1);
    if (hit && same < 0.8) { addList(p); SEARCH = c.replace(origin, ''); say(`• Search: ${c}`); break; }
  }
  if (!SEARCH) notes.push('Không tìm thấy cách search (có thể dùng POST/AJAX).');

  // 6. Write the extension
  const id = D.host(origin).replace(/[^\w.-]/g, '');
  const dir = path.join(outRoot, id);
  fs.mkdirSync(path.join(dir, 'src'), { recursive: true });
  for (const f of fs.readdirSync(path.join(__dirname, 'runtime'))) fs.copyFileSync(path.join(__dirname, 'runtime', f), path.join(dir, 'src', f));

  const cfg = {
    BASE_URL: origin,
    CHARSET: story.charset && story.charset !== 'utf-8' && story.charset !== 'utf8' ? story.charset : '',
    HEADERS: { Referer: origin + '/' },
    STORY_RE: null,
    NAME: det.name, COVER: det.cover, AUTHOR: det.author, DESC: det.desc, INFO: det.info,
    TOC: (toc && toc.sel) || '', TOC_LINK: tocLink, TOC_REVERSE: !!(toc && toc.reverse),
    CONTENT: [...new Set([content && content.sel, '#chapter-content', '#chapter-c', '.chapter-content', '.chapter-c', '#chr-content', '.reading-content', '.entry-content', '#content', '.content', 'article'].filter(Boolean))],
    LIST: lists, HOME, GENRES: GENRES.slice(0, 100), SEARCH,
  };
  const js = Object.entries(cfg).map(([k, v]) => `var ${k} = ${k === 'STORY_RE' ? `new RegExp(${JSON.stringify(pat.any)})` : Array.isArray(v) ? `[\n  ${v.map((x) => JSON.stringify(x)).join(',\n  ')}\n]` : JSON.stringify(v)};`).join('\n');
  fs.writeFileSync(path.join(dir, 'src', 'config.js'), `// Auto-generated by extension-builder from ${input}\n// Nếu site đổi giao diện/domain: chỉ cần sửa file này.\n${js}\n`);

  const script = { home: 'home.js', genre: 'genre.js', detail: 'detail.js', search: 'search.js', toc: 'toc.js', chap: 'chap.js' };
  if (!GENRES.length) delete script.genre;
  if (!SEARCH) delete script.search;
  const lang = (story.$('html').attr('lang') || '').toLowerCase();
  fs.writeFileSync(path.join(dir, 'plugin.json'), JSON.stringify({
    metadata: {
      name: id, author: 'extension-builder', version: 1, source: origin, regexp: pat.site,
      description: `Đọc truyện từ ${id}`, locale: lang.startsWith('vi') ? 'vi_VN' : lang.startsWith('zh') ? 'zh_CN' : 'en_US',
      language: 'javascript', type: 'novel',
    },
    script,
  }, null, 2));

  // Prefer real PNGs; favicon.ico is the last resort.
  const iconHref = home.error ? '' : ['link[rel~=icon][href*=".png"]', 'link[rel=apple-touch-icon]', 'link[rel~=icon]'].map((q) => home.$(q).attr('href')).find(Boolean);
  const icon = httpGet(D.abs(iconHref || '/favicon.ico', origin));
  if (icon.ok && icon.buf.length) fs.writeFileSync(path.join(dir, 'icon.png'), icon.buf);

  say(`\n✔ Đã tạo ${dir}`);
  return { dir, storyUrl: story.url, notes };
}

function test(dir, storyUrl) {
  const log = process.env.DEBUG ? say : () => {};
  const run = (file, args) => runScript(dir, file, args, log, { TOC_MAX_PAGES: 3 });
  const res = {};
  const check = (label, fn) => {
    try { const [ok, msg] = fn(); res[label] = ok; say(`${ok ? '✔' : '✘'} ${label.padEnd(7)} ${msg}`); }
    catch (e) { res[label] = false; say(`✘ ${label.padEnd(7)} lỗi: ${e.message}`); }
  };
  const meta = JSON.parse(fs.readFileSync(path.join(dir, 'plugin.json'), 'utf8'));
  let tabs = [], items = [], detail = {}, chapters = [];
  say(`\n▶ Test ${dir}`);
  check('home', () => { tabs = run('home.js', []).data; return [tabs.length > 0, `${tabs.length} tab: ${tabs.map((t) => t.title).join(', ')}`]; });
  if (tabs.length) check('gen', () => {
    const r = run('gen.js', [tabs[0].input]); items = r.data;
    const more = r.next ? run('gen.js', [tabs[0].input, r.next]).data.length : 0;
    return [items.length > 0, `${items.length} truyện, có ảnh: ${items.filter((i) => i.cover).length}, trang sau: ${r.next ? more + ' truyện' : 'không'} — "${items[0] && items[0].name}"`];
  });
  if (meta.script.genre) check('genre', () => {
    const g = run('genre.js', []).data;
    const n = g.length ? run('gen.js', [g[0].input]).data.length : 0;
    return [n > 0, `${g.length} thể loại, "${g[0] && g[0].title}" có ${n} truyện`];
  });
  const url = storyUrl || (items[0] && items[0].link);
  check('detail', () => {
    detail = run('detail.js', [url]).data;
    return [!!detail.name, `"${detail.name}" | tác giả: ${detail.author || '-'} | ảnh: ${detail.cover ? 'có' : 'không'} | mô tả: ${norm(detail.description).length} ký tự | ${detail.ongoing ? 'đang ra' : 'hoàn thành'}`];
  });
  check('toc', () => { chapters = run('toc.js', [url]).data; return [chapters.length > 0, `${chapters.length} chương (test tối đa 3 trang) — "${chapters[0] && chapters[0].name}"`]; });
  if (chapters.length) check('chap', () => {
    const r = run('chap.js', [chapters[0].url]);
    const t = norm(String(r.data || '').replace(/<[^>]+>/g, ' '));
    return [r.code === 0 && t.length > 200, `${t.length} ký tự — "${t.slice(0, 80)}..."`];
  });
  if (meta.script.search) check('search', () => {
    const key = (detail.name || 'a').split(/\s+/).slice(0, 3).join(' ');
    const r = run('search.js', [key, null]).data;
    return [r.length > 0, `"${key}" → ${r.length} kết quả`];
  });
  return res;
}

const args = process.argv.slice(2);
try {
  if (args[0] === 'test') {
    const r = test(path.resolve(args[1]), args[2]);
    process.exit(r.detail && r.toc && r.chap ? 0 : 1);
  } else if (args[0] && /^https?:\/\//.test(args[0])) {
    const o = args.indexOf('--out');
    const out = o > -1 ? args[o + 1] : path.join(__dirname, '..', '..', 'extensions');
    const { dir, storyUrl, notes } = create(args[0], out);
    const r = test(dir, storyUrl);
    for (const n of notes) say('⚠ ' + n);
    if (!(r.detail && r.toc && r.chap)) say('⚠ Chức năng đọc chưa chạy đủ — mở src/config.js để chỉnh selector, rồi chạy: node cli.js test ' + dir);
    process.exit(r.detail && r.toc && r.chap ? 0 : 1);
  } else {
    say('Cách dùng:\n  node cli.js <link-truyện-hoặc-trang-chủ> [--out <thư-mục>]\n  node cli.js test <thư-mục-extension> [link-truyện]');
  }
} catch (e) { console.error('✘ ' + e.message); process.exit(1); }
