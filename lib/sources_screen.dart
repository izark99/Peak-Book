import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'db.dart';
import 'extensions.dart';
import 'main.dart';
import 'reader_text.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late Future<List<Ext>> exts = listExtensions();

  void _reload() => setState(() => exts = listExtensions());

  Future<void> _install(Future<Ext> Function() install) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final e = await install();
      messenger.showSnackBar(SnackBar(content: Text('Đã cài ${e.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Cài lỗi: $e')));
    }
    _reload();
  }

  Future<void> _fromUrl() async {
    final ctl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cài từ URL (.zip)'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'https://...zip')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Cài')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) await _install(() => installFromUrl(url));
  }

  Future<void> _fromFile() async {
    final f = await FilePicker.pickFile();
    if (f != null) await _install(() async => installFromZip(await f.readAsBytes()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nguồn'), actions: [
          PopupMenuButton(
            icon: const Icon(Icons.add),
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _fromUrl, child: const Text('Cài từ URL')),
              PopupMenuItem(onTap: _fromFile, child: const Text('Cài từ file .zip')),
            ],
          ),
        ]),
        body: FutureBuilder(
          future: exts,
          builder: (_, snap) {
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) return const Center(child: Text('Chưa có nguồn. Bấm + để cài extension.'));
            return ListView(children: [
              for (final e in list)
                ListTile(
                  title: Text(e.name),
                  subtitle: Text('${e.source}  v${e.version}'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen(ext: e))),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await removeExtension(e);
                      _reload();
                    },
                  ),
                ),
            ]);
          },
        ),
      );
}

class SearchScreen extends StatefulWidget {
  final Ext ext;
  const SearchScreen({super.key, required this.ext});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<List>? results;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: 'Tìm trong ${widget.ext.name}', border: InputBorder.none),
            onSubmitted: (q) => setState(
                () => results = ExtRunner.instance.run(widget.ext, 'search', q.trim()).then((r) => r as List)),
          ),
        ),
        body: results == null
            ? const SizedBox()
            : FutureBuilder(
                future: results,
                builder: (_, snap) {
                  if (snap.hasError) return Center(child: Text('${snap.error}'));
                  final list = snap.data;
                  if (list == null) return const Center(child: CircularProgressIndicator());
                  if (list.isEmpty) return const Center(child: Text('Không có kết quả'));
                  return ListView(children: [
                    for (final r in list.cast<Map>())
                      ListTile(
                        leading: r['cover'] == null
                            ? null
                            : Image.network('${r['cover']}', width: 40, errorBuilder: (_, _, _) => const SizedBox()),
                        title: Text('${r['name']}'),
                        subtitle: r['author'] == null ? null : Text('${r['author']}'),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DetailScreen(ext: widget.ext, url: '${r['url']}', name: '${r['name']}'))),
                      ),
                  ]);
                },
              ),
      );
}

class DetailScreen extends StatefulWidget {
  final Ext ext;
  final String url, name;
  const DetailScreen({super.key, required this.ext, required this.url, required this.name});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final Future<(Map, List)> data = Future.wait([
    ExtRunner.instance.run(widget.ext, 'detail', widget.url),
    ExtRunner.instance.run(widget.ext, 'toc', widget.url),
  ]).then((r) => (r[0] as Map, r[1] as List));
  String? progress;

  Future<Book> _addToLibrary(Map d, List toc) async {
    final existing = await db.query('books',
        where: 'format = ? AND path = ? AND ext = ?', whereArgs: ['web', widget.url, widget.ext.id]);
    if (existing.isNotEmpty) return Book.fromMap(existing.first);
    final id = await insertBook({
      'title': d['name'] ?? widget.name,
      'author': d['author'],
      'cover': d['cover'],
      'format': 'web',
      'path': widget.url,
      'ext': widget.ext.id,
    }, [
      for (final c in toc.cast<Map>()) {'title': '${c['name']}', 'url': '${c['url']}'}
    ]);
    libraryVersion.value++;
    return Book.fromMap((await db.query('books', where: 'id = ?', whereArgs: [id])).first);
  }

  Future<void> _downloadAll(Map d, List toc) async {
    final book = await _addToLibrary(d, toc);
    final chapters = await listChapters(book.id);
    var failed = 0;
    for (var i = 0; i < chapters.length && mounted; i++) {
      setState(() => progress = 'Đang tải ${i + 1}/${chapters.length}');
      try {
        await loadChapter(book, chapters[i]);
      } catch (_) {
        failed++;
      }
    }
    if (mounted) setState(() => progress = 'Đã tải ${chapters.length - failed}/${chapters.length} chương');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: FutureBuilder(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (d, toc) = snap.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (d['cover'] != null)
                Center(
                    child: Image.network('${d['cover']}', height: 200, errorBuilder: (_, _, _) => const SizedBox())),
              Text('${d['name'] ?? widget.name}', style: Theme.of(context).textTheme.titleLarge),
              if (d['author'] != null) Text('${d['author']}'),
              const SizedBox(height: 8),
              if (d['description'] != null) Text('${d['description']}'),
              const SizedBox(height: 16),
              Text('${toc.length} chương'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Đọc'),
                  onPressed: toc.isEmpty
                      ? null
                      : () async {
                          final b = await _addToLibrary(d, toc);
                          if (context.mounted) openBook(context, b);
                        },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Tải toàn bộ'),
                  onPressed: toc.isEmpty || (progress?.startsWith('Đang') ?? false) ? null : () => _downloadAll(d, toc),
                ),
              ]),
              if (progress != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(progress!)),
            ]);
          },
        ),
      );
}
