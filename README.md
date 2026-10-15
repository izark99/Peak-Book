# Peak Book

App đọc sách cá nhân (Android, iOS build được), lấy cảm hứng từ vBook. Flutter, local-first, không backend.

## Tính năng (MVP)
- Thư viện: nhập **EPUB, MOBI/AZW/AZW3/PRC, FB2/FBZ, TXT, PDF, CBZ/ZIP**; giữ tiến độ đọc; xoá bằng nhấn giữ.
  MOBI/AZW được chuyển sang EPUB lúc nhập (thư viện `kindle_unpack`, **GPL-3**); file có DRM không mở được.
- Reader văn bản (EPUB/TXT/truyện online): cỡ chữ, sáng/tối, mục lục, bookmark.
- **TTS** bằng giọng hệ thống, tự sang chương sau, tô sáng đoạn đang đọc.
- **Dịch offline** (Google ML Kit, tải model ~30MB/ngôn ngữ lần đầu), tự nhận diện ngôn ngữ nguồn.
- **Nguồn online qua extension JS** (QuickJS): tìm → chi tiết → mục lục → đọc / tải toàn bộ về máy; nút ⟳ trong reader cập nhật chương mới cho truyện đang ra.

Chưa làm: Office (DOC/DOCX/ODT), giọng AI, trình duyệt tích hợp, sync, desktop.

## Build
```bash
flutter pub get
tool/test.sh                  # unit test (cần QuickJS lib của flutter_js, script tự tìm)
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```
CI (`.github/workflows/apk.yml`) build APK mỗi lần push; push tag `v*` sẽ đính APK vào GitHub Release.

### Ký APK cố định (nên làm một lần)
Không có key cố định thì mỗi bản build ký bằng debug key khác nhau, Android sẽ không cho cài đè và phải gỡ app (mất thư viện).
```bash
keytool -genkey -v -keystore release.jks -alias peakbook -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.jks   # copy kết quả
```
Thêm vào GitHub repo → Settings → Secrets → Actions: `ANDROID_KEYSTORE_BASE64` (chuỗi base64) và `ANDROID_KEYSTORE_PASSWORD`. Giữ file `release.jks` cẩn thận, mất là không cập nhật đè được nữa.

## Viết extension
Một extension là file `.zip` chứa thư mục có `plugin.json` và 4 script. Xem mẫu ở `extensions/sample/`.

```json
{ "id": "my-source", "name": "Tên nguồn", "version": "1", "source": "https://example.com" }
```

Mỗi script khai báo `execute(arg)` (có thể `async`) và trả về:

| Script | arg | Trả về |
|---|---|---|
| `search.js` | từ khoá | `[{name, url, author?, cover?}]` |
| `detail.js` | url truyện | `{name, author?, cover?, description?}` |
| `toc.js` | url truyện | `[{name, url}]` |
| `chap.js` | url chương | chuỗi HTML nội dung chương |

API có sẵn trong script:
- `await fetch(url, {method, headers, body})` → `{status, ok, url, text(), json()}`
- `Html.select(html, cssSelector)` → `[{text, html, outerHtml, attrs, attr(name)}]`
- `absUrl(base, href)` → URL tuyệt đối
- `SOURCE` → giá trị `source` trong `plugin.json`

Cài trong app: tab **Nguồn** → `+` → từ URL `.zip` hoặc từ file.
