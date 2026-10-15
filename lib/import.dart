import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'epub.dart';

const importExtensions = ['epub', 'txt', 'pdf', 'cbz', 'zip'];
const _imageExt = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

Future<Directory> _newBookDir() async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'books',
      DateTime.now().microsecondsSinceEpoch.toString()));
  return dir.create(recursive: true);
}

/// Copies a picked file into app storage and adds it to the library.
Future<void> importFile(PlatformFile file) async {
  final ext = (file.extension ?? '').toLowerCase();
  final name = p.basenameWithoutExtension(file.name);
  final dir = await _newBookDir();
  try {
    final src = p.join(dir.path, 'source.$ext');
    await File(src).writeAsBytes(await file.readAsBytes());
    switch (ext) {
      case 'epub':
        await extractFileToDisk(src, dir.path);
        final info = await parseEpubDir(dir.path);
        await insertBook(
          {'title': info.title, 'author': info.author, 'cover': info.cover, 'format': 'epub', 'path': dir.path},
          [for (final c in info.chapters) {'title': c.title, 'url': c.path}],
        );
      case 'txt':
        final text = utf8.decode(await File(src).readAsBytes(), allowMalformed: true);
        await insertBook(
          {'title': name, 'format': 'txt', 'path': src},
          [for (final c in splitTxt(text)) {'title': c.title, 'content': c.html}],
        );
      case 'pdf':
        await insertBook({'title': name, 'format': 'pdf', 'path': src}, []);
      case 'cbz' || 'zip':
        final pages = p.join(dir.path, 'pages');
        await extractFileToDisk(src, pages);
        await File(src).delete();
        final images = comicPages(pages);
        if (images.isEmpty) throw const FormatException('Không có ảnh trong file');
        await insertBook({'title': name, 'format': 'cbz', 'path': pages, 'cover': images.first}, []);
      default:
        throw FormatException('Chưa hỗ trợ định dạng .$ext');
    }
  } catch (_) {
    await dir.delete(recursive: true);
    rethrow;
  }
}

/// Image files of an extracted comic, in natural order (2.jpg before 10.jpg).
List<String> comicPages(String dir) {
  final files = Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((f) => _imageExt.contains(p.extension(f).toLowerCase()))
      .toList();
  files.sort(_natural);
  return files;
}

int _natural(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final x = re.allMatches(a).map((m) => m[0]!).toList(), y = re.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final n = int.tryParse(x[i]), m = int.tryParse(y[i]);
    final c = n != null && m != null ? n.compareTo(m) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

final _chapterLine = RegExp(r'^\s*((Chương|Chapter|Hồi|Quyển|第)\s*[\dIVXLCDM一二三四五六七八九十百千]+.*)$',
    multiLine: true, caseSensitive: false);

/// Splits plain text into chapters on "Chương N" style headings; falls back to ~20k-char parts.
List<({String title, String html})> splitTxt(String text) {
  String toHtml(String s) => s
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => '<p>${const HtmlEscape().convert(l)}</p>')
      .join();

  final heads = _chapterLine.allMatches(text).toList();
  if (heads.length >= 2) {
    final out = <({String title, String html})>[];
    if (text.substring(0, heads.first.start).trim().isNotEmpty) {
      out.add((title: 'Mở đầu', html: toHtml(text.substring(0, heads.first.start))));
    }
    for (var i = 0; i < heads.length; i++) {
      final end = i + 1 < heads.length ? heads[i + 1].start : text.length;
      out.add((title: heads[i][1]!.trim(), html: toHtml(text.substring(heads[i].end, end))));
    }
    return out;
  }
  const size = 20000;
  final out = <({String title, String html})>[];
  for (var start = 0; start < text.length;) {
    var end = (start + size).clamp(0, text.length);
    final nl = text.indexOf('\n', end);
    end = nl == -1 || end == text.length ? text.length : nl;
    out.add((title: 'Phần ${out.length + 1}', html: toHtml(text.substring(start, end))));
    start = end;
  }
  return out.isEmpty ? [(title: 'Phần 1', html: '')] : out;
}
