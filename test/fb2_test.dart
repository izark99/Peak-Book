import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peak_book/fb2.dart';
import 'package:peak_book/import.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info>
  <author><first-name>Nguyễn</first-name><last-name>Du</last-name></author>
  <book-title>Truyện Kiều</book-title>
  <coverpage><image l:href="#cover.jpg"/></coverpage>
</title-info></description>
<body>
  <title><p>Truyện Kiều</p></title>
  <section><title><p>Hồi 1</p></title>
    <p>Trăm năm <emphasis>trong cõi</emphasis> <strong>người ta</strong> &lt;x&gt;</p>
    <empty-line/>
    <poem><stanza><v>Dòng một</v><v>Dòng hai</v></stanza></poem>
    <section><title><p>Đoạn con</p></title><p>Nội dung con</p></section>
  </section>
  <section><p>Không tiêu đề</p></section>
</body>
<body name="notes"><section id="n1"><p>Chú thích 1</p></section></body>
<binary id="cover.jpg" content-type="image/jpeg">/9j/4AAQ</binary>
</FictionBook>''';

void main() {
  test('parseFb2 builds chapters, metadata and images', () async {
    final dir = await Directory.systemTemp.createTemp('fb2');
    addTearDown(() => dir.delete(recursive: true));
    final book = parseFb2(_xml, dir.path);

    expect(book.title, 'Truyện Kiều');
    expect(book.author, 'Nguyễn Du');
    expect(File(book.cover!).readAsBytesSync(), [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    expect(book.chapters.map((c) => c.title), ['Hồi 1', 'Phần 2', 'Ghi chú']);

    final html = book.chapters[0].html;
    expect(html, startsWith('<h2>Truyện Kiều</h2>')); // body title rides with the first chapter
    expect(html, contains('<h2>Hồi 1</h2>'));
    expect(html, contains('<p>Trăm năm <i>trong cõi</i> <b>người ta</b> &lt;x&gt;</p>'));
    expect(html, contains('<blockquote><p>Dòng một<br>Dòng hai<br></p></blockquote>'));
    expect(html, contains('<h3>Đoạn con</h3><p>Nội dung con</p>'));
    expect(book.chapters[2].html, contains('Chú thích 1'));
  });

  test('decodeFb2 handles windows-1251 prolog', () {
    final bytes = [
      ...'<?xml version="1.0" encoding="windows-1251"?><p>'.codeUnits,
      0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, // Привет
      ...'</p>'.codeUnits,
    ];
    expect(decodeFb2(bytes), contains('<p>Привет</p>'));
  });

  test('formatOf treats .fb2.zip as fbz', () {
    expect(formatOf('Sach.FB2.zip'), 'fbz');
    expect(formatOf('comic.zip'), 'zip');
    expect(formatOf('a.fb2'), 'fb2');
  });
}
