import 'package:flutter_test/flutter_test.dart';
import 'package:peak_book/browser_screen.dart';

void main() {
  test('toUrl adds scheme, keeps urls, searches otherwise', () {
    expect(toUrl('example.com/a?b=1'), 'https://example.com/a?b=1');
    expect(toUrl('http://x.vn'), 'http://x.vn');
    expect(toUrl('truyện hay'), 'https://www.google.com/search?q=truy%E1%BB%87n+hay');
    expect(toUrl('localhost'), startsWith('https://www.google.com/search'));
  });
}
