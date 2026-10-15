import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:html/parser.dart' as html_parser;

import 'db.dart';
import 'extensions.dart';
import 'main.dart';

/// Chapter HTML: DB cache first, then the EPUB file or the source extension (cached afterwards).
Future<String> loadChapter(Book b, Chapter c) async {
  final cached = await chapterContent(c.id);
  if (cached != null) return cached;
  if (b.format == 'web') {
    final ext = (await listExtensions()).where((e) => e.id == b.ext).firstOrNull;
    if (ext == null) throw ExtError('Chưa cài nguồn "${b.ext}"');
    final html = '${await ExtRunner.instance.run(ext, 'chap', c.url)}';
    await saveChapterContent(c.id, html);
    return html;
  }
  return html_parser.parse(await File(c.url!).readAsString()).body?.innerHtml ?? '';
}

/// Readable paragraphs of a chapter, used for TTS and translation.
List<String> paragraphs(String html) {
  final body = html_parser.parse(html).body;
  if (body == null) return [];
  final blocks = body
      .querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote, pre')
      .where((e) => e.querySelector('p, li, blockquote') == null)
      .map((e) => e.text.trim());
  final out = blocks.where((t) => t.isNotEmpty).toList();
  return out.isNotEmpty ? out : body.text.split(RegExp(r'\n+')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

class TextReader extends StatefulWidget {
  final Book book;
  const TextReader({super.key, required this.book});
  @override
  State<TextReader> createState() => _TextReaderState();
}

class _TextReaderState extends State<TextReader> {
  Book get book => widget.book;
  List<Chapter> chapters = [];
  int index = 0;
  String? html;
  Object? error;
  final scroll = ScrollController();

  // Paragraph mode (TTS / translation)
  List<String> paras = [];
  List<String>? translated;
  bool translating = false, showTranslation = false, speaking = false;
  int speakingAt = -1;
  List<GlobalKey> paraKeys = [];
  final tts = FlutterTts();
  String? sourceLang;

  @override
  void initState() {
    super.initState();
    tts.awaitSpeakCompletion(true);
    scroll.addListener(_trackOffset);
    listChapters(book.id).then((c) {
      chapters = c;
      _open(book.progress.clamp(0, (c.length - 1).clamp(0, 1 << 30)), book.offset);
    });
  }

  @override
  void dispose() {
    speaking = false;
    tts.stop();
    saveProgress(book);
    scroll.dispose();
    super.dispose();
  }

  void _trackOffset() {
    if (scroll.hasClients && scroll.position.maxScrollExtent > 0) {
      book.offset = (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1);
    }
  }

  Future<void> _open(int i, [double offset = 0]) async {
    if (chapters.isEmpty) return setState(() => error = 'Sách không có chương nào');
    setState(() {
      index = i;
      html = null;
      error = null;
      translated = null;
      speakingAt = -1;
    });
    book.progress = i;
    book.offset = offset;
    saveProgress(book);
    try {
      final h = await loadChapter(book, chapters[i]);
      if (!mounted || index != i) return;
      setState(() {
        html = h;
        paras = paragraphs(h);
        paraKeys = List.generate(paras.length, (_) => GlobalKey());
      });
      _prefetchNext(i);
      if (showTranslation) _translate();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // HTML layout can settle over a few frames; retry the jump briefly.
        for (var t = 0; t < 5 && mounted && scroll.hasClients; t++) {
          scroll.jumpTo(offset * scroll.position.maxScrollExtent);
          await Future.delayed(const Duration(milliseconds: 60));
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  void _prefetchNext(int i) {
    if (book.format == 'web' && i + 1 < chapters.length) {
      loadChapter(book, chapters[i + 1]).ignore();
    }
  }

  Future<String> _detectLang() async {
    if (sourceLang != null) return sourceLang!;
    final id = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      return sourceLang = await id.identifyLanguage(paras.take(20).join(' '));
    } finally {
      id.close();
    }
  }

  Future<void> _translate() async {
    if (paras.isEmpty || translating) return;
    final i = index;
    setState(() => translating = true);
    try {
      final src = BCP47Code.fromRawValue(await _detectLang());
      final target = Settings.targetLang.value;
      if (src == null) throw 'Không nhận diện được ngôn ngữ ($sourceLang)';
      if (src == target) {
        translated = paras;
      } else {
        final t = OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);
        try {
          final out = <String>[];
          for (final para in paras) {
            out.add(await t.translateText(para));
            if (!mounted || index != i) return;
            if (out.length % 10 == 0 || out.length == paras.length) setState(() => translated = [...out]);
          }
        } finally {
          t.close();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dịch lỗi: $e')));
        setState(() => showTranslation = false);
      }
    } finally {
      if (mounted) setState(() => translating = false);
    }
  }

  Future<void> _toggleSpeak() async {
    if (speaking) {
      setState(() => speaking = false);
      await tts.stop();
      return;
    }
    setState(() => speaking = true);
    var start = speakingAt >= 0 ? speakingAt : (book.offset * paras.length).floor();
    while (speaking && mounted) {
      final lines = showTranslation && translated != null ? translated! : paras;
      await tts.setSpeechRate(Settings.ttsRate.value);
      final lang = showTranslation ? Settings.targetLang.value.bcpCode : await _detectLang();
      if (lang != 'und') await tts.setLanguage(lang);
      for (var p = start.clamp(0, lines.length); p < lines.length && speaking && mounted; p++) {
        setState(() => speakingAt = p);
        final ctx = paraKeys.elementAtOrNull(p)?.currentContext;
        if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.2, duration: const Duration(milliseconds: 300));
        await tts.speak(lines[p]);
      }
      if (!speaking || !mounted) break;
      if (index + 1 >= chapters.length) break;
      await _open(index + 1);
      start = 0;
    }
    if (mounted) setState(() => speaking = false);
  }

  bool refreshing = false;

  /// Re-runs the source's toc.js and appends chapters published since the book was added.
  Future<void> _refreshToc() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => refreshing = true);
    try {
      final ext = (await listExtensions()).where((e) => e.id == book.ext).firstOrNull;
      if (ext == null) throw ExtError('Chưa cài nguồn "${book.ext}"');
      final toc = await ExtRunner.instance.run(ext, 'toc', book.path) as List;
      final added = await appendChapters(
          book.id, [for (final c in toc.cast<Map>()) (title: '${c['name']}', url: '${c['url']}')]);
      final list = await listChapters(book.id);
      if (!mounted) return;
      setState(() => chapters = list);
      messenger.showSnackBar(SnackBar(content: Text(added == 0 ? 'Không có chương mới' : 'Thêm $added chương mới')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Cập nhật mục lục lỗi: $e')));
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> _addBookmark() async {
    final label = '${chapters[index].title} · ${(book.offset * 100).round()}%';
    await addBookmark(book.id, index, book.offset, label);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu: $label')));
  }

  void _showBookmarks() => showModalBottomSheet(
        context: context,
        builder: (c) => FutureBuilder(
          future: listBookmarks(book.id),
          builder: (_, snap) => ListView(children: [
            for (final m in snap.data ?? <Map<String, Object?>>[])
              ListTile(
                title: Text(m['label'] as String),
                onTap: () {
                  Navigator.pop(c);
                  _open(m['chapter'] as int, m['offset'] as double);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await deleteBookmark(m['id'] as int);
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
              ),
            if (snap.data?.isEmpty ?? false) const ListTile(title: Text('Chưa có bookmark')),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = chapters.isEmpty ? book.title : chapters[index].title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (book.format == 'web')
            IconButton(
              tooltip: 'Cập nhật mục lục',
              icon: refreshing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: refreshing ? null : _refreshToc,
            ),
          IconButton(icon: const Icon(Icons.bookmark_add_outlined), onPressed: html == null ? null : _addBookmark),
          IconButton(icon: const Icon(Icons.bookmarks_outlined), onPressed: _showBookmarks),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (c, i) => ListTile(
              selected: i == index,
              title: Text(chapters[i].title),
              onTap: () {
                Navigator.pop(c);
                _open(i);
              },
            ),
          ),
        ),
      ),
      body: _body(),
      bottomNavigationBar: BottomAppBar(
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: index > 0 ? () => _open(index - 1) : null),
          IconButton(
            tooltip: 'Đọc to',
            icon: Icon(speaking ? Icons.stop_circle_outlined : Icons.record_voice_over_outlined),
            onPressed: paras.isEmpty ? null : _toggleSpeak,
          ),
          IconButton(
            tooltip: 'Dịch',
            isSelected: showTranslation,
            icon: translating
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.translate),
            onPressed: paras.isEmpty
                ? null
                : () {
                    setState(() => showTranslation = !showTranslation);
                    if (showTranslation && translated == null) _translate();
                  },
          ),
          IconButton(
              icon: const Icon(Icons.text_decrease),
              onPressed: () => Settings.fontSize.value = (Settings.fontSize.value - 1).clamp(12, 32)),
          IconButton(
              icon: const Icon(Icons.text_increase),
              onPressed: () => Settings.fontSize.value = (Settings.fontSize.value + 1).clamp(12, 32)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: index + 1 < chapters.length ? () => _open(index + 1) : null,
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text('$error', textAlign: TextAlign.center)),
          FilledButton(onPressed: () => _open(index, book.offset), child: const Text('Thử lại')),
        ]),
      );
    }
    final h = html;
    if (h == null) return const Center(child: CircularProgressIndicator());
    final url = chapters[index].url;
    return ValueListenableBuilder(
      valueListenable: Settings.fontSize,
      builder: (context, size, _) {
        final style = TextStyle(fontSize: size, height: 1.6);
        final paraMode = showTranslation || speakingAt >= 0;
        final lines = showTranslation ? (translated ?? const <String>[]) : paras;
        return SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          child: SelectionArea(
            child: paraMode
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var i = 0; i < lines.length; i++)
                      Container(
                        key: i < paraKeys.length ? paraKeys[i] : null,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: i == speakingAt ? Theme.of(context).colorScheme.primaryContainer : null,
                        child: Text(lines[i], style: style),
                      ),
                  ])
                : HtmlWidget(
                    h,
                    textStyle: style,
                    baseUrl: url == null ? null : (book.format == 'web' ? Uri.tryParse(url) : Uri.file(url)),
                  ),
          ),
        );
      },
    );
  }
}
