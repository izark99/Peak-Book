import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peak_book/epub.dart';
import 'package:peak_book/import.dart';

void main() {
  test('parseEpubDir reads metadata, cover, spine order and nav titles', () async {
    final files = {
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
      'OEBPS/content.opf': '''<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
<metadata><dc:title>Sách Thử</dc:title><dc:creator>Tác Giả</dc:creator><meta name="cover" content="img"/></metadata>
<manifest>
  <item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>
  <item id="img" href="images/cover.jpg" media-type="image/jpeg"/>
  <item id="c2" href="text/ch%202.xhtml" media-type="application/xhtml+xml"/>
  <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>''',
      'OEBPS/nav.xhtml': '<html><body><nav><ol><li><a href="text/ch1.xhtml#a">Chương Một</a></li></ol></nav></body></html>',
      'OEBPS/text/ch1.xhtml': '<html><body><p>1</p></body></html>',
      'OEBPS/text/ch 2.xhtml': '<html><body><p>2</p></body></html>',
    };
    final archive = Archive();
    files.forEach((k, v) => archive.add(ArchiveFile.bytes(k, utf8.encode(v))));
    final dir = await Directory.systemTemp.createTemp('epub');
    addTearDown(() => dir.delete(recursive: true));
    await extractArchiveToDisk(ZipDecoder().decodeBytes(ZipEncoder().encode(archive)), dir.path);

    final info = await parseEpubDir(dir.path);
    expect(info.title, 'Sách Thử');
    expect(info.author, 'Tác Giả');
    expect(info.cover, p.join(dir.path, 'OEBPS', 'images', 'cover.jpg'));
    expect(info.chapters.map((c) => c.title), ['Chương Một', 'Phần 2']);
    expect(info.chapters.map((c) => File(c.path).existsSync()), [true, true]);
  });

  test('MOBI converts to an EPUB that parseEpubDir can read', () async {
    // Fixture: Project Gutenberg #1342 (public domain), copied from the kindle_unpack package.
    final dir = await Directory.systemTemp.createTemp('mobi');
    addTearDown(() => dir.delete(recursive: true));
    final epub = p.join(dir.path, 'book.epub');
    await kindleToEpub('test/fixtures/pg1342.mobi', epub);
    await unzipToDir(epub, dir.path);

    final info = await parseEpubDir(dir.path);
    expect(info.title, contains('Pride and Prejudice'));
    expect(info.author, contains('Austen'));
    expect(info.chapters, isNotEmpty);
    final text = (await Future.wait(info.chapters.map((c) => File(c.path).readAsString()))).join();
    expect(text, contains('truth universally acknowledged'));
  });

  test('kindleToEpub rejects non-Kindle bytes with FormatException', () async {
    final dir = await Directory.systemTemp.createTemp('mobi');
    addTearDown(() => dir.delete(recursive: true));
    final bad = File(p.join(dir.path, 'bad.mobi'))..writeAsStringSync('not a mobi file');
    await expectLater(kindleToEpub(bad.path, p.join(dir.path, 'x.epub')), throwsA(isA<FormatException>()));
  });

  test('splitTxt splits on chapter headings and escapes html', () {
    final parts = splitTxt('Lời tựa\nChương 1: A\n<b>x</b>\n\nChương 2\ny\n');
    expect(parts.map((c) => c.title), ['Mở đầu', 'Chương 1: A', 'Chương 2']);
    expect(parts[1].html, '<p>&lt;b&gt;x&lt;&#47;b&gt;</p>');
  });

  test('splitTxt without headings falls back to size-based parts', () {
    final parts = splitTxt(List.filled(3000, 'mười ký tự').join('\n'));
    expect(parts.length, 2);
    expect(parts.first.title, 'Phần 1');
  });
}
