import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// An installed source extension: a folder with plugin.json + search/detail/toc/chap.js.
///
/// Each script defines `execute(arg)` (may be async) and returns JSON-able data:
///   search.js  execute(query) -> [{name, url, cover?, author?}]
///   detail.js  execute(url)   -> {name, author?, cover?, description?}
///   toc.js     execute(url)   -> [{name, url}]
///   chap.js    execute(url)   -> html string
/// Host API: fetch(url, {method, headers, body}) -> {status, ok, url, text()},
///           Html.select(html, css) -> [{text, html, outerHtml, attrs, attr(name)}],
///           absUrl(base, href), SOURCE (plugin.json "source").
class Ext {
  final String id, name, version, source, dir;
  Ext(this.dir, Map<String, dynamic> j)
      : id = j['id'] as String? ?? p.basename(dir),
        name = j['name'] as String? ?? p.basename(dir),
        version = '${j['version'] ?? ''}',
        source = j['source'] as String? ?? '';
}

class ExtError implements Exception {
  final String message;
  ExtError(this.message);
  @override
  String toString() => message;
}

Future<Directory> _root() async =>
    Directory(p.join((await getApplicationDocumentsDirectory()).path, 'extensions')).create(recursive: true);

Future<List<Ext>> listExtensions([Directory? root]) async {
  final out = <Ext>[];
  for (final d in (root ?? await _root()).listSync().whereType<Directory>()) {
    final f = File(p.join(d.path, 'plugin.json'));
    if (f.existsSync()) out.add(Ext(d.path, jsonDecode(await f.readAsString())));
  }
  return out..sort((a, b) => a.name.compareTo(b.name));
}

Future<Ext> installFromUrl(String url) async {
  final r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) throw ExtError('HTTP ${r.statusCode}');
  return installFromZip(r.bodyBytes);
}

/// Installs (or replaces) an extension from a zip; plugin.json may sit at the root or in one subfolder.
Future<Ext> installFromZip(Uint8List bytes, [Directory? root]) async {
  root ??= await _root();
  final tmp = await Directory.systemTemp.createTemp('ext');
  try {
    await extractArchiveToDisk(ZipDecoder().decodeBytes(bytes), tmp.path);
    final manifest = tmp
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.basename(f.path) == 'plugin.json')
        .fold<File?>(null, (a, f) => a == null || f.path.length < a.path.length ? f : a);
    if (manifest == null) throw ExtError('Không tìm thấy plugin.json');
    final j = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final id = '${j['id'] ?? j['name'] ?? ''}'.replaceAll(RegExp(r'[^\w.-]'), '_');
    if (id.isEmpty) throw ExtError('plugin.json thiếu id');
    final dest = Directory(p.join(root.path, id));
    if (dest.existsSync()) await dest.delete(recursive: true);
    await dest.create();
    for (final f in manifest.parent.listSync(recursive: true).whereType<File>()) {
      final out = File(p.join(dest.path, p.relative(f.path, from: manifest.parent.path)));
      await out.parent.create(recursive: true);
      await f.copy(out.path);
    }
    return Ext(dest.path, j);
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<void> removeExtension(Ext e) => Directory(e.dir).delete(recursive: true);

List<Map<String, Object?>> selectHtml(String html, String css) => html_parser
    .parse(html)
    .querySelectorAll(css)
    .map((e) => {
          'text': e.text.trim(),
          'html': e.innerHtml,
          'outerHtml': e.outerHtml,
          'attrs': e.attributes.map((k, v) => MapEntry('$k', v)),
        })
    .toList();

const _prelude = r'''
var __peak = { n: 0, p: {} };
function fetch(url, opts) {
  return new Promise(function (resolve, reject) {
    var id = ++__peak.n;
    __peak.p[id] = { resolve: resolve, reject: reject };
    sendMessage('peak_fetch', JSON.stringify({ id: id, url: String(url), opts: opts || {} }));
  });
}
function __peakFetched(id, err, res) {
  var p = __peak.p[id]; delete __peak.p[id];
  if (err) return p.reject(new Error(err));
  res.text = function () { return Promise.resolve(res.body); };
  res.json = function () { return Promise.resolve(JSON.parse(res.body)); };
  p.resolve(res);
}
var Html = {
  select: function (html, css) {
    return JSON.parse(sendMessage('peak_select', JSON.stringify([String(html), css]))).map(function (e) {
      e.attr = function (n) { return e.attrs[n] || ''; };
      return e;
    });
  }
};
function absUrl(base, href) { return JSON.parse(sendMessage('peak_abs', JSON.stringify([base, href]))); }
''';

/// Runs extension scripts in one shared JS runtime. Each run is wrapped in its own function scope.
// ponytail: one shared runtime + 15s timeout; give each extension its own runtime if globals ever clash.
class ExtRunner {
  static ExtRunner? _instance;
  static ExtRunner get instance => _instance ??= ExtRunner();

  final JavascriptRuntime _js = getJavascriptRuntime(xhr: false);
  final _client = http.Client();
  final _pending = <int, Completer<Object?>>{};
  int _seq = 0;
  Duration timeout = const Duration(seconds: 15);

  ExtRunner() {
    _js.onMessage('peak_select', (a) => jsonEncode(selectHtml(a[0] as String, a[1] as String)));
    _js.onMessage('peak_abs', (a) => jsonEncode(Uri.parse(a[0] as String).resolve(a[1] as String).toString()));
    _js.onMessage('peak_fetch', (a) => _fetch(a['id'] as int, a['url'] as String, a['opts'] as Map));
    _js.onMessage('peak_result', (a) {
      final c = _pending.remove(a['id']);
      if (c == null) return;
      a.containsKey('error') ? c.completeError(ExtError('${a['error']}')) : c.complete(a['value']);
    });
    final r = _js.evaluate(_prelude);
    if (r.isError) throw ExtError(r.stringResult);
  }

  Future<void> _fetch(int id, String url, Map opts) async {
    String result;
    try {
      final req = http.Request((opts['method'] as String? ?? 'GET').toUpperCase(), Uri.parse(url))
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36'
        ..headers.addAll({for (final e in (opts['headers'] as Map? ?? {}).entries) '${e.key}': '${e.value}'});
      if (opts['body'] != null) req.body = '${opts['body']}';
      final res = await http.Response.fromStream(await _client.send(req).timeout(timeout));
      // ponytail: UTF-8 only; add charset sniffing (gbk, etc.) if a source needs it.
      result = 'null, ${jsonEncode({
            'status': res.statusCode,
            'ok': res.statusCode >= 200 && res.statusCode < 300,
            'url': res.request?.url.toString() ?? url,
            'body': utf8.decode(res.bodyBytes, allowMalformed: true),
          })}';
    } catch (e) {
      result = '${jsonEncode('$e')}, null';
    }
    _js.evaluate('__peakFetched($id, $result)');
  }

  Future<Object?> run(Ext ext, String script, Object? arg) async {
    final file = File(p.join(ext.dir, '$script.js'));
    if (!file.existsSync()) throw ExtError('${ext.name} thiếu $script.js');
    final id = ++_seq;
    final done = Completer<Object?>();
    _pending[id] = done;
    final r = _js.evaluate('''(function () {
var SOURCE = ${jsonEncode(ext.source)};
${await file.readAsString()}
;Promise.resolve().then(function () { return execute(${jsonEncode(arg)}); }).then(
  function (v) { sendMessage('peak_result', JSON.stringify({ id: $id, value: v === undefined ? null : v })); },
  function (e) { sendMessage('peak_result', JSON.stringify({ id: $id, error: String((e && e.message) || e) })); });
})();''', sourceUrl: '${ext.id}/$script.js');
    if (r.isError) {
      _pending.remove(id);
      throw ExtError(r.stringResult);
    }
    final pump = Timer.periodic(const Duration(milliseconds: 10), (_) => _js.executePendingJob());
    try {
      return await done.future.timeout(timeout * 2);
    } on TimeoutException {
      throw ExtError('${ext.name}/$script.js quá thời gian');
    } finally {
      pump.cancel();
      _pending.remove(id);
    }
  }
}
