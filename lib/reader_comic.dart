import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'import.dart';

class ComicReader extends StatefulWidget {
  final Book book;
  const ComicReader({super.key, required this.book});
  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader> {
  late final pages = comicPages(widget.book.path);
  late final controller = PageController(initialPage: widget.book.progress.clamp(0, pages.length - 1));

  @override
  void dispose() {
    saveProgress(widget.book);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text('${widget.book.title} · ${widget.book.progress + 1}/${pages.length}')),
        body: PageView.builder(
          controller: controller,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => widget.book.progress = i),
          itemBuilder: (_, i) => InteractiveViewer(child: Image.file(File(pages[i]), fit: BoxFit.contain)),
        ),
      );
}
