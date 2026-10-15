import 'package:flutter_test/flutter_test.dart';
import 'package:peak_book/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await openDb(inMemoryDatabasePath);
  });

  test('appendChapters adds only new urls, after existing ones, keeping cache', () async {
    final id = await insertBook({'title': 'T', 'format': 'web', 'path': 'u', 'ext': 'e'}, [
      {'title': 'C1', 'url': 'a'},
      {'title': 'C2', 'url': 'b'},
    ]);
    final first = (await listChapters(id)).first;
    await saveChapterContent(first.id, '<p>cached</p>');

    final added = await appendChapters(id, [(title: 'C1', url: 'a'), (title: 'C2', url: 'b'), (title: 'C3', url: 'c')]);
    expect(added, 1);
    final list = await listChapters(id);
    expect(list.map((c) => (c.idx, c.title)), [(0, 'C1'), (1, 'C2'), (2, 'C3')]);
    expect(await chapterContent(first.id), '<p>cached</p>');
    expect(await appendChapters(id, [(title: 'C3', url: 'c')]), 0);
  });
}
