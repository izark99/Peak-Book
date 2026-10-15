import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'extensions.dart';
import 'sources_screen.dart';

/// Turns address-bar input into a url: adds https://, or searches when it doesn't look like a host.
String toUrl(String input) {
  final s = input.trim();
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
  if (!s.contains(' ') && RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?(/.*)?$').hasMatch(s)) return 'https://$s';
  return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(s)}';
}

class BrowserScreen extends StatefulWidget {
  final String? url;
  const BrowserScreen({super.key, this.url});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final address = TextEditingController();
  late final WebViewController web;
  List<Ext> exts = [];
  Ext? match;
  int progress = 100;
  bool canBack = false, canForward = false;

  @override
  void initState() {
    super.initState();
    listExtensions().then((e) => exts = e);
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => progress = p),
        onUrlChange: (c) => _onUrl(c.url),
        onPageFinished: (url) {
          _onUrl(url);
          _captureCookies(url);
        },
      ));
    if (widget.url != null) _go(widget.url!);
  }

  void _go(String input) {
    final url = toUrl(input);
    address.text = url;
    web.loadRequest(Uri.parse(url));
  }

  Future<void> _onUrl(String? url) async {
    if (url == null || !mounted) return;
    final back = await web.canGoBack(), forward = await web.canGoForward();
    if (!mounted) return;
    setState(() {
      address.text = url;
      match = extForUrl(exts, url);
      canBack = back;
      canForward = forward;
    });
  }

  Future<void> _captureCookies(String url) async {
    try {
      var c = await web.runJavaScriptReturningResult('document.cookie');
      // Android returns a JSON-encoded string, iOS the raw string.
      if (c is String && c.startsWith('"')) c = jsonDecode(c);
      final host = Uri.parse(url).host;
      if (host.isNotEmpty) await CookieJar.set(host, '$c');
    } catch (_) {
      // Pages without JS access (e.g. about:blank) have no cookies to share.
    }
  }

  void _add() {
    final e = match;
    if (e == null) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => DetailScreen(ext: e, url: address.text, name: e.name)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !canBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) web.goBack();
        },
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: TextField(
              controller: address,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(hintText: 'Nhập địa chỉ hoặc từ khoá', border: InputBorder.none),
              onSubmitted: _go,
              onTap: () => address.selection = TextSelection(baseOffset: 0, extentOffset: address.text.length),
            ),
            bottom: progress < 100
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(2),
                    child: LinearProgressIndicator(value: progress / 100, minHeight: 2))
                : null,
          ),
          body: WebViewWidget(controller: web),
          bottomNavigationBar: BottomAppBar(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: canBack ? web.goBack : null),
              IconButton(icon: const Icon(Icons.arrow_forward), onPressed: canForward ? web.goForward : null),
              IconButton(icon: const Icon(Icons.refresh), onPressed: web.reload),
              FilledButton.icon(
                icon: const Icon(Icons.library_add),
                label: Text(match == null ? 'Không có nguồn' : 'Thêm (${match!.name})'),
                onPressed: match == null ? null : _add,
              ),
            ]),
          ),
        ),
      );
}
