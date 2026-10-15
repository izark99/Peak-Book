// Vbook-compatible runtime emulator: sync fetch + Jsoup-like API over cheerio.
// Used both by the generator (to fetch/parse) and by `test` (to run generated scripts locally).
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const cheerio = require('cheerio');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// Vbook's fetch is synchronous, so emulate it with a child process running Node's fetch.
const CHILD = `const [u,o]=process.argv.slice(1);const t=setTimeout(()=>{process.stdout.write('{"status":0,"error":"timeout"}');process.exit()},30000);
fetch(u,JSON.parse(o)).then(async r=>{const b=Buffer.from(await r.arrayBuffer());clearTimeout(t);
process.stdout.write(JSON.stringify({status:r.status,url:r.url,headers:Object.fromEntries(r.headers),body:b.toString('base64')}))})
.catch(e=>{clearTimeout(t);process.stdout.write(JSON.stringify({status:0,error:String(e.cause||e)}))})`;

function httpGet(url, opts = {}) {
  url = String(url);
  if (opts.queries) url += (url.includes('?') ? '&' : '?') + new URLSearchParams(opts.queries);
  let body = opts.body;
  if (body && typeof body === 'object') body = new URLSearchParams(body).toString();
  const init = { method: opts.method || 'GET', headers: { 'user-agent': UA, ...(opts.headers || {}) }, body, redirect: 'follow' };
  const out = execFileSync(process.execPath, ['-e', CHILD, url, JSON.stringify(init)], { maxBuffer: 128 << 20 });
  const r = JSON.parse(out);
  r.buf = Buffer.from(r.body || '', 'base64');
  r.ok = r.status >= 200 && r.status < 300;
  r.url = r.url || url;
  return r;
}

function charsetOf(r) {
  const m = /charset=["']?([\w-]+)/i.exec((r.headers && r.headers['content-type']) || '') ||
    /<meta[^>]+charset=["']?([\w-]+)/i.exec(r.buf.subarray(0, 4096).toString('latin1'));
  return m ? m[1].toLowerCase() : 'utf-8';
}

function decode(r, charset) {
  try { return new TextDecoder(charset || charsetOf(r)).decode(r.buf); } catch { return r.buf.toString('utf8'); }
}

const norm = (s) => String(s || '').replace(/\s+/g, ' ').trim();

// One wrapper serves as both Jsoup Element and Elements.
class J {
  constructor($, sel) { this.$ = $; this.s = sel; }
  select(q) { return new J(this.$, this.s.find(q)); }
  first() { return this.s.length ? new J(this.$, this.s.first()) : null; }
  last() { return this.s.length ? new J(this.$, this.s.last()) : null; }
  get(i) { return new J(this.$, this.s.eq(i)); }
  size() { return this.s.length; }
  isEmpty() { return !this.s.length; }
  text() { return this.s.toArray().map((n) => norm(this.$(n).text())).filter(Boolean).join(' '); }
  ownText() { return norm(this.s.first().contents().filter((_, n) => n.type === 'text').text()); }
  html() { return this.s.toArray().map((n) => this.$(n).html() || '').join('\n'); }
  outerHtml() { return this.s.toArray().map((n) => this.$.html(n)).join('\n'); }
  attr(k) { for (const n of this.s.toArray()) { const v = this.$(n).attr(k); if (v != null) return v; } return ''; }
  hasAttr(k) { return this.s.toArray().some((n) => this.$(n).attr(k) != null); }
  tagName() { return (this.s[0] && this.s[0].name) || ''; }
  parent() { return new J(this.$, this.s.parent()); }
  children() { return new J(this.$, this.s.children()); }
  remove() { this.s.remove(); return this; }
  forEach(fn) { this.s.toArray().forEach((n, i) => fn(new J(this.$, this.$(n)), i)); }
}

function parseHtml(html) { const $ = cheerio.load(html); return new J($, $.root()); }

function response(r) {
  return {
    ok: r.ok, status: r.status, url: r.url, headers: r.headers || {}, error: r.error,
    text: (cs) => decode(r, cs),
    html: (cs) => parseHtml(decode(r, cs)),
    json: () => JSON.parse(decode(r)),
  };
}

// Run an extension script (src/<file>) the way Vbook does: load() shares one global scope.
function runScript(extDir, file, args, log = () => {}, overrides = {}) {
  const src = path.join(extDir, 'src');
  const ctx = vm.createContext({
    fetch: (u, o) => { log('  fetch ' + u); return response(httpGet(u, o)); },
    Html: { parse: parseHtml },
    Response: { success: (data, next) => ({ code: 0, data, next }), error: (data) => ({ code: 1, data }) },
    Console: { log: (...a) => log('  log ' + a.join(' ')) },
    console, sleep: () => {}, encodeURIComponent, decodeURIComponent,
  });
  ctx.load = (f) => vm.runInContext(fs.readFileSync(path.join(src, f), 'utf8'), ctx, { filename: f });
  ctx.load(file);
  Object.assign(ctx, overrides);
  return vm.runInContext('execute', ctx).apply(null, args);
}

module.exports = { httpGet, decode, charsetOf, parseHtml, response, runScript, norm, UA };
