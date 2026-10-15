import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

late Database db;

Future<void> openDb([String? path]) async {
  db = await openDatabase(
    path ?? p.join(await getDatabasesPath(), 'peak_book.db'),
    version: 1,
    onCreate: (d, _) async {
      // format: epub | txt | pdf | cbz | web. path: local folder/file, or book url for web.
      // progress: chapter index (text) or page index (pdf/cbz); offset: scroll fraction in chapter.
      await d.execute('''CREATE TABLE books(
        id INTEGER PRIMARY KEY, title TEXT NOT NULL, author TEXT, cover TEXT,
        format TEXT NOT NULL, path TEXT NOT NULL, ext TEXT,
        progress INTEGER NOT NULL DEFAULT 0, offset REAL NOT NULL DEFAULT 0,
        added INTEGER NOT NULL)''');
      // url: chapter file path (epub) or chapter url (web). content: cached html.
      await d.execute('''CREATE TABLE chapters(
        id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        idx INTEGER NOT NULL, title TEXT NOT NULL, url TEXT, content TEXT)''');
      await d.execute('CREATE INDEX chapters_book ON chapters(book_id, idx)');
      await d.execute('''CREATE TABLE bookmarks(
        id INTEGER PRIMARY KEY, book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter INTEGER NOT NULL, offset REAL NOT NULL, label TEXT NOT NULL, created INTEGER NOT NULL)''');
    },
    onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
  );
}

class Book {
  final int id;
  final String title, format, path;
  final String? author, cover, ext;
  int progress;
  double offset;

  Book.fromMap(Map<String, Object?> m)
      : id = m['id'] as int,
        title = m['title'] as String,
        author = m['author'] as String?,
        cover = m['cover'] as String?,
        format = m['format'] as String,
        path = m['path'] as String,
        ext = m['ext'] as String?,
        progress = m['progress'] as int,
        offset = (m['offset'] as num).toDouble();
}

class Chapter {
  final int id, idx;
  final String title;
  final String? url;
  String? content;

  Chapter.fromMap(Map<String, Object?> m)
      : id = m['id'] as int,
        idx = m['idx'] as int,
        title = m['title'] as String,
        url = m['url'] as String?,
        content = m['content'] as String?;
}

Future<List<Book>> listBooks() async =>
    (await db.query('books', orderBy: 'added DESC')).map(Book.fromMap).toList();

Future<int> insertBook(Map<String, Object?> book, List<Map<String, Object?>> chapters) =>
    db.transaction((t) async {
      final id = await t.insert('books', {...book, 'added': DateTime.now().millisecondsSinceEpoch});
      final b = t.batch();
      for (var i = 0; i < chapters.length; i++) {
        b.insert('chapters', {...chapters[i], 'book_id': id, 'idx': i});
      }
      await b.commit(noResult: true);
      return id;
    });

Future<void> deleteBook(int id) => db.delete('books', where: 'id = ?', whereArgs: [id]);

Future<void> saveProgress(Book b) =>
    db.update('books', {'progress': b.progress, 'offset': b.offset}, where: 'id = ?', whereArgs: [b.id]);

/// Chapter list without content (content can be large).
Future<List<Chapter>> listChapters(int bookId) async => (await db.query('chapters',
        columns: ['id', 'idx', 'title', 'url', 'NULL AS content'],
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'idx'))
    .map(Chapter.fromMap)
    .toList();

Future<String?> chapterContent(int chapterId) async =>
    (await db.query('chapters', columns: ['content'], where: 'id = ?', whereArgs: [chapterId]))
        .first['content'] as String?;

Future<void> saveChapterContent(int chapterId, String html) =>
    db.update('chapters', {'content': html}, where: 'id = ?', whereArgs: [chapterId]);

Future<int> countCached(int bookId) async => Sqflite.firstIntValue(await db.rawQuery(
    'SELECT COUNT(*) FROM chapters WHERE book_id = ? AND content IS NOT NULL', [bookId]))!;

Future<List<Map<String, Object?>>> listBookmarks(int bookId) =>
    db.query('bookmarks', where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created DESC');

Future<void> addBookmark(int bookId, int chapter, double offset, String label) => db.insert('bookmarks', {
      'book_id': bookId,
      'chapter': chapter,
      'offset': offset,
      'label': label,
      'created': DateTime.now().millisecondsSinceEpoch,
    });

Future<void> deleteBookmark(int id) => db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
