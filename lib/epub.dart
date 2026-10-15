import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class EpubInfo {
  final String title;
  final String? author, cover;
  final List<({String title, String path})> chapters;
  EpubInfo(this.title, this.author, this.cover, this.chapters);
}

/// Reads an already-extracted EPUB folder: container.xml -> OPF -> spine (+ nav/ncx titles).
Future<EpubInfo> parseEpubDir(String dir) async {
  final container = XmlDocument.parse(await File(p.join(dir, 'META-INF', 'container.xml')).readAsString());
  final opfPath = p.join(dir, container.findAllElements('rootfile').first.getAttribute('full-path')!);
  final opfDir = p.dirname(opfPath);
  final opf = XmlDocument.parse(await File(opfPath).readAsString());

  String meta(String name) => opf.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name)
      .map((e) => e.innerText.trim())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');

  final items = {
    for (final e in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item'))
      e.getAttribute('id')!: e,
  };
  String full(String href) => p.normalize(p.join(opfDir, Uri.decodeFull(href.split('#').first)));

  // Cover: EPUB3 properties="cover-image", else EPUB2 <meta name="cover" content="id">.
  final coverId = opf.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'meta' && e.getAttribute('name') == 'cover')
      .map((e) => e.getAttribute('content'))
      .firstOrNull;
  final coverItem = items.values.where((e) => (e.getAttribute('properties') ?? '').contains('cover-image')).firstOrNull ??
      items[coverId];

  final titles = await _tocTitles(opf, items, full);
  final spine = opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'itemref');
  final chapters = <({String title, String path})>[];
  for (final ref in spine) {
    final item = items[ref.getAttribute('idref')];
    if (item == null) continue;
    final path = full(item.getAttribute('href')!);
    chapters.add((title: titles[path] ?? 'Phần ${chapters.length + 1}', path: path));
  }

  return EpubInfo(
    meta('title').isEmpty ? p.basename(dir) : meta('title'),
    meta('creator').isEmpty ? null : meta('creator'),
    coverItem == null ? null : full(coverItem.getAttribute('href')!),
    chapters,
  );
}

/// Maps chapter file path -> title from EPUB3 nav or EPUB2 NCX. First title per file wins.
Future<Map<String, String>> _tocTitles(
    XmlDocument opf, Map<String, XmlElement> items, String Function(String) full) async {
  final out = <String, String>{};
  final nav = items.values.where((e) => (e.getAttribute('properties') ?? '').split(' ').contains('nav')).firstOrNull;
  final ncxId = opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'spine').first.getAttribute('toc');
  final ncx = items[ncxId] ?? items.values.where((e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml').firstOrNull;
  try {
    if (nav != null) {
      final navPath = full(nav.getAttribute('href')!);
      final doc = XmlDocument.parse(await File(navPath).readAsString());
      for (final a in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'a')) {
        final href = a.getAttribute('href');
        if (href == null) continue;
        out.putIfAbsent(p.normalize(p.join(p.dirname(navPath), Uri.decodeFull(href.split('#').first))), () => a.innerText.trim());
      }
    } else if (ncx != null) {
      final ncxPath = full(ncx.getAttribute('href')!);
      final doc = XmlDocument.parse(await File(ncxPath).readAsString());
      for (final np in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'navPoint')) {
        final src = np.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'content').getAttribute('src')!;
        final label = np.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'text').innerText.trim();
        out.putIfAbsent(p.normalize(p.join(p.dirname(ncxPath), Uri.decodeFull(src.split('#').first))), () => label);
      }
    }
  } catch (_) {
    // Broken TOC is common; fall back to generic titles.
  }
  return out;
}
