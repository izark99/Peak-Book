import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class Fb2Book {
  final String title;
  final String? author, cover;
  final List<({String title, String html})> chapters;
  Fb2Book(this.title, this.author, this.cover, this.chapters);
}

/// Parses FictionBook 2 XML into chapters of HTML. Embedded images are written to [imageDir].
/// Each top-level <section> of a body becomes a chapter; a "notes" body becomes one chapter.
Fb2Book parseFb2(String xml, String imageDir) {
  final doc = XmlDocument.parse(xml);
  Iterable<XmlElement> all(XmlNode n, String name) => n.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
  XmlElement? child(XmlElement e, String name) => e.childElements.where((c) => c.name.local == name).firstOrNull;
  String? href(XmlElement e) =>
      e.attributes.where((a) => a.name.local == 'href').firstOrNull?.value.replaceFirst(RegExp('^#'), '');

  // Images: <binary id="x" content-type="image/jpeg">base64</binary>
  final images = <String, String>{};
  for (final b in all(doc, 'binary')) {
    final id = b.getAttribute('id');
    if (id == null) continue;
    try {
      final file = File(p.join(imageDir, id.replaceAll(RegExp(r'[^\w.-]'), '_')));
      file.writeAsBytesSync(base64.decode(b.innerText.replaceAll(RegExp(r'\s'), '')));
      images[id] = file.path;
    } on FormatException {
      // Skip broken base64.
    }
  }

  final info = all(doc, 'title-info').firstOrNull;
  final title = info == null ? null : child(info, 'book-title')?.innerText.trim();
  final authorEl = info == null ? null : child(info, 'author');
  final author = authorEl == null
      ? null
      : ['first-name', 'middle-name', 'last-name', 'nickname']
          .map((n) => child(authorEl, n)?.innerText.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .join(' ');
  final coverImg = info == null ? null : all(info, 'coverpage').expand((c) => all(c, 'image')).firstOrNull;

  final esc = const HtmlEscape();
  String inline(XmlNode n) {
    if (n is XmlText || n is XmlCDATA) return esc.convert(n.value ?? '');
    if (n is! XmlElement) return '';
    final inner = n.children.map(inline).join();
    return switch (n.name.local) {
      'strong' => '<b>$inner</b>',
      'emphasis' => '<i>$inner</i>',
      'strikethrough' => '<s>$inner</s>',
      'sub' || 'sup' || 'code' => '<${n.name.local}>$inner</${n.name.local}>',
      'image' => _img(images[href(n)]),
      'tr' => '<tr>$inner</tr>',
      'td' || 'th' => '<td>$inner</td>',
      _ => inner,
    };
  }

  String block(XmlElement e, int depth) {
    final kids = e.childElements;
    return switch (e.name.local) {
      'p' => '<p>${inline(e)}</p>',
      'empty-line' => '<br>',
      'subtitle' => '<h4>${inline(e)}</h4>',
      'title' => '<h${(depth + 1).clamp(2, 5)}>${kids.map(inline).join('<br>')}</h${(depth + 1).clamp(2, 5)}>',
      'image' => _img(images[href(e)]),
      'text-author' => '<p><i>${inline(e)}</i></p>',
      'v' => '${inline(e)}<br>',
      'stanza' => '<p>${kids.map((k) => block(k, depth)).join()}</p>',
      'epigraph' || 'poem' || 'cite' => '<blockquote>${kids.map((k) => block(k, depth)).join()}</blockquote>',
      'table' => '<table>${e.children.map(inline).join()}</table>',
      'section' => kids.map((k) => block(k, depth + 1)).join(),
      _ => kids.map((k) => block(k, depth)).join(),
    };
  }

  String sectionTitle(XmlElement s, String fallback) {
    final t = child(s, 'title')?.childElements.map((p) => p.innerText.trim()).where((t) => t.isNotEmpty).join(' – ');
    return t == null || t.isEmpty ? fallback : t;
  }

  final chapters = <({String title, String html})>[];
  for (final body in doc.rootElement.childElements.where((e) => e.name.local == 'body')) {
    final sections = body.childElements.where((e) => e.name.local == 'section').toList();
    if (body.getAttribute('name') == 'notes' || sections.isEmpty) {
      final name = body.getAttribute('name') == 'notes' ? 'Ghi chú' : sectionTitle(body, 'Phần ${chapters.length + 1}');
      chapters.add((title: name, html: body.childElements.map((k) => block(k, 0)).join()));
      continue;
    }
    // Body-level title/epigraph go with the first chapter.
    final lead = body.childElements.takeWhile((e) => e.name.local != 'section').map((k) => block(k, 0)).join();
    for (final s in sections) {
      chapters.add((
        title: sectionTitle(s, 'Phần ${chapters.length + 1}'),
        html: (s == sections.first ? lead : '') + block(s, 0),
      ));
    }
  }

  return Fb2Book(
    title == null || title.isEmpty ? 'Không tên' : title,
    author == null || author.isEmpty ? null : author,
    coverImg == null ? null : images[href(coverImg)],
    chapters.isEmpty ? [(title: 'Phần 1', html: '')] : chapters,
  );
}

String _img(String? path) => path == null ? '' : '<img src="${Uri.file(path)}">';

/// FB2 is usually UTF-8; Russian files are often windows-1251, declared in the XML prolog.
String decodeFb2(List<int> bytes) {
  final head = latin1.decode(bytes.take(200).toList());
  if (RegExp(r'encoding="(windows|cp)-?1251"', caseSensitive: false).hasMatch(head)) {
    return String.fromCharCodes(bytes.map((b) => b < 0x80 ? b : _cp1251[b - 0x80]));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

final _cp1251 = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, //
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  // 0xC0-0xFF map to А..я (U+0410..U+044F)
  for (var c = 0x0410; c <= 0x044F; c++) c,
];
