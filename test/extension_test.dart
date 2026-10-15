import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peak_book/extensions.dart';

// Needs the QuickJS shared lib: run via tool/test.sh (sets LIBQUICKJSC_TEST_PATH).
void main() {
  late HttpServer server;
  late Ext ext;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final file = path == '/search'
          ? 'search.html'
          : path.startsWith('/book/')
              ? 'book.html'
              : path == '/chap/1'
                  ? 'chap.html'
                  : null;
      req.response.headers.contentType = ContentType.html;
      if (file == null) {
        req.response.statusCode = 404;
      } else {
        req.response.add(await File('test/fixtures/site/$file').readAsBytes());
      }
      await req.response.close();
    });
    ext = Ext('extensions/sample', {'id': 'sample', 'name': 'Sample', 'source': 'http://127.0.0.1:${server.port}'});
  });
  tearDownAll(() => server.close());

  String base() => 'http://127.0.0.1:${server.port}';

  test('search -> detail -> toc -> chap', () async {
    final js = ExtRunner.instance;
    final results = await js.run(ext, 'search', 'một') as List;
    expect(results, hasLength(2));
    expect(results[0], {'name': 'Truyện Một', 'url': '${base()}/book/1', 'author': 'Tác giả A'});
    expect(results[1]['name'], r'Truyện "Hai" `x` ${y}');

    final detail = await js.run(ext, 'detail', '${base()}/book/1') as Map;
    expect(detail['cover'], '${base()}/img/1.jpg');
    expect(detail['description'], 'Mô tả ngắn.');

    final toc = await js.run(ext, 'toc', '${base()}/book/1') as List;
    expect(toc.map((c) => c['name']), ['Chương 1: Mở đầu', 'Chương 2']);

    final chap = await js.run(ext, 'chap', toc[0]['url']) as String;
    expect(chap, contains('Đoạn một.'));
    expect(chap, contains(r'`hai` ${x}'));
  });

  test('script errors surface as ExtError', () async {
    await expectLater(ExtRunner.instance.run(ext, 'chap', '${base()}/chap/404'), throwsA(isA<ExtError>()));
    await expectLater(ExtRunner.instance.run(ext, 'missing', null), throwsA(isA<ExtError>()));
  });
}
