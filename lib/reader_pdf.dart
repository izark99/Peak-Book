import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'db.dart';

class PdfReader extends StatefulWidget {
  final Book book;
  const PdfReader({super.key, required this.book});
  @override
  State<PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<PdfReader> {
  int? page;

  @override
  void dispose() {
    saveProgress(widget.book);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(page == null ? widget.book.title : '${widget.book.title} · trang $page')),
        body: PdfViewer.file(
          widget.book.path,
          initialPageNumber: widget.book.progress + 1,
          params: PdfViewerParams(
            onPageChanged: (n) {
              if (n == null) return;
              widget.book.progress = n - 1;
              setState(() => page = n);
            },
          ),
        ),
      );
}
