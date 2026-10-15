// Heuristics that read a novel site and produce the selectors in config.js.
const cheerio = require('cheerio');
const { httpGet, decode, charsetOf, norm } = require('./shim');

const CHAPTER_RE = /((ch(ư|u)(ơ|o)ng|chapter|chap|ch\.|h(ồ|o)i|quy(ể|e)n|t(ậ|a)p|episode|ep\.?)\s*[:.#]?\s*\d+|第\s*[\d一二三四五六七八九十百千零]+\s*[章回节話话])/i;
const IDENT = /^[a-zA-Z_-][\w-]*$/;
const DYNAMIC = /\d{3,}|^(active|current|selected|show|hidden|in|open|odd|even|first|last|clearfix|lazy\w*)$/i;
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function load(url) {
  const r = httpGet(url);
  if (!r.ok) return { error: `HTTP ${r.status}${r.error ? ' ' + r.error : ''}`, url };
  const html = decode(r);
  // Cloudflare / JS-only pages have almost no real markup.
  if (/<title>Just a moment|cf-browser-verification|cf_chl_opt/i.test(html))
    return { error: 'Bị Cloudflare chặn (cần trình duyệt)', url };
  return { $: cheerio.load(html), url: r.url, charset: charsetOf(r) };
}

function abs(href, base) {
  try {
    if (!href || /^(javascript|mailto|data):|^#/i.test(href.trim())) return '';
    const u = new URL(href.trim(), base); u.hash = ''; return u.href;
  } catch { return ''; }
}
const host = (u) => { try { return new URL(u).hostname.replace(/^www\./, ''); } catch { return ''; } };

// Apps (React/Next/Vue...) ship data + code instead of content: inline scripts dominate the HTML.
// Measured: Wattpad 25-46%, plain HTML novel sites 0-3%.
function jsRendered(page) {
  if (!page || !page.$) return false;
  const html = page.$.html();
  const scripts = page.$('script:not([src])').toArray().reduce((n, s) => n + (page.$(s).html() || '').length, 0);
  return scripts / html.length >= 0.2 || /__NEXT_DATA__|__NUXT__|data-reactroot|ng-version|window\.__remixContext/.test(html);
}
const JS_MSG = 'Site render bằng JavaScript (kiểu app React/Next/Vue): HTML tải về không chứa danh sách chương/nội dung, nên tool không tự nhận diện được. ' +
  'Cần viết tay extension gọi thẳng API JSON của site (mở DevTools > Network > Fetch/XHR để tìm API). Mẫu: extensions/wattpad.com.';

// ---------- selector building ----------
const classes = (el) => ((el.attribs && el.attribs.class) || '').split(/\s+/).filter((c) => c && IDENT.test(c) && !DYNAMIC.test(c));
function token(el, withId = true) {
  const id = el.attribs && el.attribs.id;
  if (withId && id && IDENT.test(id) && !/\d{3,}/.test(id)) return `${el.name}#${id}`;
  return el.name + classes(el).map((c) => '.' + c).join('');
}
function ancestors(el) { const a = []; for (let p = el.parent; p && p.type === 'tag'; p = p.parent) a.push(p); return a; }
function first($, sel) { try { return $(sel)[0]; } catch { return null; } }

// Shortest descendant selector matching only el (else: whose first match is el).
function single($, el) {
  const parts = [token(el)];
  let fallback = null;
  const ok = (s) => {
    try { const m = $(s); if (m[0] !== el) return false; if (m.length === 1) return true; fallback = fallback || s; } catch {}
    return false;
  };
  if (ok(parts[0])) return parts[0];
  for (const p of ancestors(el)) {
    const t = token(p);
    if (t === p.name && p.name !== 'body') continue;
    parts.unshift(t);
    if (ok(parts.join(' '))) return parts.join(' ');
  }
  const exact = [el, ...ancestors(el)].reverse().map((n) => token(n, false)).join(' > ');
  return ok(exact) ? exact : fallback || (first($, exact) === el ? exact : null);
}

function lca(els) {
  let common = ancestors(els[0]);
  for (const e of els.slice(1)) { const s = new Set(ancestors(e)); common = common.filter((x) => s.has(x)); }
  return common[0];
}

// Selector matching all els (and little else).
function listSel($, els) {
  const L = lca(els);
  if (!L) return null;
  const path = [];
  for (let n = els[0]; n !== L; n = n.parent) path.unshift(n);
  const base = single($, L) || token(L, false);
  const cands = [
    `${base} > ${path.map((n) => n.name).join(' > ')}`,
    `${base} > ${path.map((n) => token(n, false)).join(' > ')}`,
    `${base} ${token(els[0], false)}`,
  ];
  for (const c of cands) {
    try {
      const m = new Set($(c).toArray());
      if (els.every((e) => m.has(e)) && m.size <= els.length * 1.2 + 2) return c;
    } catch {}
  }
  return null;
}

const signature = (el) => [el, ...ancestors(el)].reverse().map((n) => token(n, false)).join('>');

// Links grouped by DOM position: a repeated list (chapters, stories) shares one signature.
function groups(page, keep) {
  const g = new Map();
  page.$('a[href]').each((_, a) => {
    const u = abs(a.attribs.href, page.url);
    if (!u || !keep(u, a)) return;
    const k = signature(a);
    if (!g.has(k)) g.set(k, []);
    g.get(k).push(a);
  });
  return [...g.values()];
}

const text = ($, el) => norm($(el).text()) || norm($(el).attr('title'));
const isChapter = ($, a) => CHAPTER_RE.test(text($, a)) || /^\d+\s*[.:\-–]/.test(text($, a)) || /(chuong|chapter|chap)[-_/]?\d+/i.test(a.attribs.href);

// Chapters of one story share a parent path; "latest chapters" of many stories don't.
function sameStory(g, base) {
  const count = {};
  for (const a of g) { const d = abs(a.attribs.href, base).replace(/[^/]*\/?$/, ''); count[d] = (count[d] || 0) + 1; }
  return Math.max(...Object.values(count)) / g.length >= 0.7;
}

// ---------- story URL pattern ----------
function storyPattern(url) {
  const x = new URL(url);
  let p;
  if (x.search && /\d/.test(x.search)) {
    p = esc(x.pathname) + esc(x.search).replace(/\d+/g, '\\d+') + '(?:#.*)?$';
  } else {
    const segs = x.pathname.replace(/\/$/, '').split('/');
    const last = segs.length - 1;
    // keep a trailing numeric id / extension: "slug.123", "slug-123.html", "123.html"
    const tail = (segs[last].match(/([._-]?\d+)?(\.[a-z]{2,5})?$/i) || [''])[0];
    const head = segs[last].length > tail.length ? '[^/?#]+' : '';
    const tailRe = esc(tail).replace(/\d+/g, '\\d+');
    p = segs.map((s, i) => (i === last ? head + tailRe : esc(s).replace(/\d+/g, '\\d+'))).join('/') + '/?(?:[?#].*)?$';
  }
  return { any: '^https?://[^/]+' + p, site: '^https?://(?:www\\.)?' + esc(host(url)) + p };
}

// ---------- page detectors ----------
function detectToc(page, storyRe) {
  const { $ } = page;
  let best = null, bs = 0;
  for (const g of groups(page, (u) => u !== page.url && host(u) === host(page.url) && !(storyRe && storyRe.test(u)))) {
    const ratio = g.filter((a) => isChapter($, a)).length / g.length;
    if (g.length < 2 || ratio < 0.6 || !sameStory(g, page.url)) continue;
    if (g.length * ratio > bs) { bs = g.length * ratio; best = g; }
  }
  if (!best) return null;
  const num = (a) => { const m = text($, a).match(/\d+/); return m ? +m[0] : NaN; };
  return {
    sel: listSel($, best),
    links: best.map((a) => ({ name: text($, a), url: abs(a.attribs.href, page.url) })),
    reverse: num(best[0]) > num(best[best.length - 1]),
  };
}

// TOC on the story page, or on a linked "all chapters" page (which beats a partial "latest chapters" list).
function findToc(story, storyRe) {
  let toc = detectToc(story, storyRe), tocLink = '';
  const a = story.$('a[href]').toArray().find((x) => /(danh sách chương|mục lục|tất cả chương|all chapters|chapter list|table of contents|view all|目录|全部章节)/i.test(text(story.$, x)) || /\/(chapters|muc-luc|danh-sach-chuong)\/?$/.test(x.attribs.href));
  if (a) {
    const p = load(abs(a.attribs.href, story.url));
    const t = !p.error && detectToc(p, storyRe);
    if (t && (!toc || t.links.length > toc.links.length)) { toc = t; tocLink = single(story.$, a) || ''; }
  }
  // A chapter page links to its own TOC too; it is not a story page.
  if (toc && toc.links.some((l) => l.url.replace(/\/$/, '') === story.url.replace(/\/$/, ''))) return { toc: null, tocLink: '' };
  return { toc, tocLink };
}

const INLINE = new Set(['p', 'span', 'font', 'em', 'i', 'b', 'strong', 'u', 'small', 'big']);
const SKIP = new Set(['script', 'style', 'a', 'p', 'span', 'li', 'ul', 'ol', 'nav', 'header', 'footer', 'h1', 'h2', 'h3', 'h4', 'select', 'option', 'b', 'i', 'em', 'strong', 'font', 'br', 'img', 'noscript', 'button', 'form', 'input', 'textarea', 'head', 'title', 'meta', 'link']);

// Readability-style: the element whose own text + paragraph children is largest wins.
function detectContent(page) {
  const { $ } = page;
  let best = null, bs = 0;
  $('body, body *').each((_, el) => {
    if (SKIP.has(el.name)) return;
    let score = 0;
    for (const c of el.children) {
      if (c.type === 'text') score += c.data.trim().length;
      else if (c.type === 'tag' && INLINE.has(c.name)) score += norm($(c).text()).length;
    }
    if (score <= bs) return;
    const total = norm($(el).text()).length || 1;
    if (norm($(el).find('a').text()).length / total > 0.3) return;
    bs = score; best = el;
  });
  return bs > 150 ? { sel: single(page.$, best), len: bs } : null;
}

function detectDetail(page) {
  const { $ } = page;
  const og = norm($('meta[property="og:title"]').attr('content'));
  const r = { name: [], cover: [], author: [], desc: [], info: '' };

  // Name: a heading that matches og:title, else the first h1.
  let nameEl = null;
  for (const sel of ['h1', 'h2', 'h3', '[class*=title]', '[itemprop=name]']) {
    nameEl = $(sel).toArray().find((e) => { const t = norm($(e).text()); return t && t.length < 200 && og && (og.includes(t) || t.includes(og)); });
    if (nameEl) break;
  }
  nameEl = nameEl || $('h1')[0];
  if (nameEl) r.name.push([single($, nameEl), 'text']);
  r.name.push(['meta[property="og:title"]', 'content'], ['h1', 'text'], ['title', 'text']);
  r.name = r.name.filter((x, i) => r.name.findIndex((y) => y[0] === x[0]) === i);

  // Cover: the <img> that shows og:image, else an image near the title.
  const ogImg = abs($('meta[property="og:image"]').attr('content'), page.url);
  const imgUrl = (e) => ['data-src', 'data-original', 'data-lazy-src', 'src'].map((k) => abs($(e).attr(k), page.url)).find(Boolean);
  let imgEl = ogImg && $('img').toArray().find((e) => imgUrl(e) === ogImg);
  if (!imgEl && nameEl) for (const p of ancestors(nameEl).slice(0, 5)) { imgEl = $(p).find('img')[0]; if (imgEl) break; }
  if (imgEl) r.cover.push([single($, imgEl), 'img']);
  r.cover.push(['meta[property="og:image"]', 'content']);

  // Author: a link to an author page, else a "Tác giả:" label.
  let authorEl = $('a[href]').toArray().find((a) => /(tac-?gia|author|writer|tacgia|作者)/i.test(a.attribs.href) && norm($(a).text()));
  if (!authorEl) authorEl = $('[itemprop=author]')[0] || $('body *').toArray().find((e) => /^(tác giả|author|作\s*者)\s*[:：]/i.test(norm($(e).text())) && norm($(e).text()).length < 80);
  if (authorEl) r.author.push([single($, authorEl), 'text']);
  r.author.push(['meta[name="author"]', 'content'], ['meta[property="book:author"]', 'content']);

  // Description: innermost block whose class/id says so (outer ones also wrap other info).
  const descs = $('div, p, section, span, article').toArray()
    .filter((e) => /(desc|summary|intro|synopsis|gioi-?thieu|tom-?tat|about|blurb|简介)/i.test(`${e.attribs.class || ''} ${e.attribs.id || ''} ${e.attribs.itemprop || ''}`) && norm($(e).text()).length >= 50);
  const descEl = descs.find((e) => !descs.some((d) => d !== e && ancestors(d).includes(e)));
  if (descEl) r.desc.push([single($, descEl), 'html']);
  r.desc.push(['meta[name="description"]', 'content'], ['meta[property="og:description"]', 'content']);

  // Info box (status, genres): the author's container that mentions status/genre.
  if (authorEl) {
    const box = ancestors(authorEl).slice(0, 6).find((p) => /(trạng thái|tình trạng|status|thể loại|genre|状态|分类)/i.test($(p).text()) && $(p).text().length < 3000);
    if (box) r.info = single($, box) || '';
  }
  return { r, nameEl: nameEl ? norm($(nameEl).text()) : og };
}

function detectList(page, storyRe) {
  const { $ } = page;
  let best = null, bs = 0;
  for (const g of groups(page, (u) => storyRe.test(u) && host(u) === host(page.url))) {
    if (g.length < 3) continue;
    const set = new Set(g);
    const items = g.map((a) => {
      let n = a;
      while (n.parent && n.parent.type === 'tag' && n.parent.name !== 'body' && $(n.parent).find('a').toArray().filter((x) => set.has(x)).length === 1) n = n.parent;
      return n;
    });
    const imgRatio = items.filter((n) => $(n).find('img').length).length / items.length;
    const score = g.length * (1 + imgRatio);
    if (score > bs) { bs = score; best = { g, items }; }
  }
  if (!best) return null;
  const item = listSel($, best.items);
  if (!item) return null;
  const a0 = best.g[0], i0 = best.items[0];
  if (a0 === i0) return { item, link: '', count: best.g.length };
  const path = [];
  for (let n = a0; n !== i0; n = n.parent) path.unshift(n);
  for (const link of [path.map((n) => token(n, false)).join(' > '), path.map((n) => n.name).join(' > '), token(a0, false)]) {
    const ok = best.items.filter((it, i) => { try { return $(it).find(link)[0] === best.g[i]; } catch { return false; } }).length;
    if (ok >= best.items.length * 0.8) return { item, link, count: best.g.length };
  }
  return null;
}

module.exports = { jsRendered, JS_MSG, findToc, listSel, load, abs, host, storyPattern, detectToc, detectContent, detectDetail, detectList, groups, isChapter, text, CHAPTER_RE, single };
