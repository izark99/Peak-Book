import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'import.dart';
import 'reader_comic.dart';
import 'reader_pdf.dart';
import 'reader_text.dart';
import 'sources_screen.dart';

/// App-wide settings, persisted in SharedPreferences.
class Settings {
  static late SharedPreferences _prefs;
  static final dark = ValueNotifier(false);
  static final fontSize = ValueNotifier(18.0);
  static final targetLang = ValueNotifier(TranslateLanguage.vietnamese);
  static final ttsRate = ValueNotifier(0.5);

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    dark.value = _prefs.getBool('dark') ?? false;
    fontSize.value = _prefs.getDouble('fontSize') ?? 18;
    targetLang.value = TranslateLanguage.values.byName(_prefs.getString('targetLang') ?? 'vietnamese');
    ttsRate.value = _prefs.getDouble('ttsRate') ?? 0.5;
    dark.addListener(() => _prefs.setBool('dark', dark.value));
    fontSize.addListener(() => _prefs.setDouble('fontSize', fontSize.value));
    targetLang.addListener(() => _prefs.setString('targetLang', targetLang.value.name));
    ttsRate.addListener(() => _prefs.setDouble('ttsRate', ttsRate.value));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([openDb(), Settings.load()]);
  runApp(const PeakBookApp());
}

class PeakBookApp extends StatelessWidget {
  const PeakBookApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: Settings.dark,
        builder: (_, dark, _) => MaterialApp(
          title: 'Peak Book',
          theme: ThemeData(colorSchemeSeed: Colors.teal),
          darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: [const LibraryScreen(), const SourcesScreen(), const SettingsScreen()][tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.library_books_outlined), label: 'Thư viện'),
            NavigationDestination(icon: Icon(Icons.extension_outlined), label: 'Nguồn'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Cài đặt'),
          ],
        ),
      );
}

/// Bumped whenever the library changes (import, add from source, delete).
final libraryVersion = ValueNotifier(0);

Future<void> openBook(BuildContext context, Book b) async {
  final screen = switch (b.format) {
    'pdf' => PdfReader(book: b),
    'cbz' => ComicReader(book: b),
    _ => TextReader(book: b),
  };
  await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  libraryVersion.value++;
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final files = await FilePicker.pickFiles();
    for (final f in files) {
      try {
        if (!importExtensions.contains((f.extension ?? '').toLowerCase())) {
          throw FormatException('Chưa hỗ trợ ${f.name}');
        }
        await importFile(f);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Lỗi nhập ${f.name}: $e')));
      }
    }
    libraryVersion.value++;
  }

  Future<void> _delete(BuildContext context, Book b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Xoá "${b.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    await deleteBook(b.id);
    if (b.format != 'web') {
      final dir = Directory(b.format == 'epub' ? b.path : p.dirname(b.path));
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
    libraryVersion.value++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Thư viện')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _import(context),
          icon: const Icon(Icons.add),
          label: const Text('Nhập file'),
        ),
        body: ValueListenableBuilder(
          valueListenable: libraryVersion,
          builder: (_, _, _) => FutureBuilder(
            future: listBooks(),
            builder: (context, snap) {
              final books = snap.data;
              if (books == null) return const Center(child: CircularProgressIndicator());
              if (books.isEmpty) {
                return const Center(child: Text('Chưa có sách. Nhập EPUB/TXT/PDF/CBZ hoặc thêm từ Nguồn.'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140, childAspectRatio: 0.55, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: books.length,
                itemBuilder: (_, i) => BookTile(
                  book: books[i],
                  onTap: () => openBook(context, books[i]),
                  onLongPress: () => _delete(context, books[i]),
                ),
              );
            },
          ),
        ),
      );
}

class BookTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap, onLongPress;
  const BookTile({super.key, required this.book, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cover = book.cover;
    final placeholder = Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(book.title, textAlign: TextAlign.center, maxLines: 5, overflow: TextOverflow.ellipsis),
    );
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.expand(
              child: cover == null
                  ? placeholder
                  : cover.startsWith('http')
                      ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
                      : Image.file(File(cover), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
        Text(book.format.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cài đặt')),
        body: ListenableBuilder(
          listenable: Listenable.merge([Settings.dark, Settings.fontSize, Settings.targetLang, Settings.ttsRate]),
          builder: (_, _) => ListView(children: [
            SwitchListTile(
              title: const Text('Giao diện tối'),
              value: Settings.dark.value,
              onChanged: (v) => Settings.dark.value = v,
            ),
            ListTile(
              title: Text('Cỡ chữ: ${Settings.fontSize.value.round()}'),
              subtitle: Slider(
                  min: 12, max: 32, divisions: 20, value: Settings.fontSize.value,
                  onChanged: (v) => Settings.fontSize.value = v),
            ),
            ListTile(
              title: Text('Tốc độ đọc TTS: ${Settings.ttsRate.value.toStringAsFixed(2)}'),
              subtitle: Slider(
                  min: 0.1, max: 1, divisions: 18, value: Settings.ttsRate.value,
                  onChanged: (v) => Settings.ttsRate.value = v),
            ),
            ListTile(
              title: const Text('Dịch sang'),
              trailing: DropdownButton<TranslateLanguage>(
                value: Settings.targetLang.value,
                onChanged: (v) => Settings.targetLang.value = v!,
                items: [
                  for (final l in TranslateLanguage.values) DropdownMenuItem(value: l, child: Text(l.name)),
                ],
              ),
            ),
          ]),
        ),
      );
}
