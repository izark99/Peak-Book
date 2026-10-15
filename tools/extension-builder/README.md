# Extension Builder

Tạo extension đọc truyện (định dạng giống Vbook) chỉ từ 1 link web nguồn.

```bash
cd tools/extension-builder && npm install
node cli.js https://truyenfull.live/                  # link trang chủ hoặc link 1 truyện
node cli.js https://site.com/ten-truyen/ --out ./out  # chọn thư mục output
node cli.js test ../../extensions/truyenfull.live      # chạy lại test cho extension
node cli.js pack ../../extensions/truyenfull.live      # đóng gói lại plugin.zip sau khi sửa tay
npm test                                               # self-check offline của heuristics
```

Mặc định extension được ghi vào `extensions/<domain>/`. Sau khi tạo, tool tự chạy test trên site thật
(home → gen → genre → detail → toc → chap → search) và in ✔/✘ cho từng bước.

## Cách hoạt động

1. Tìm 1 trang truyện mẫu (nếu link đưa vào là trang chủ: dò các nhóm link, đi sâu tối đa 2 cấp).
2. Trên trang truyện: nhận diện tên, ảnh bìa, tác giả, mô tả, khung thông tin, danh sách chương
   (kể cả khi danh sách nằm ở trang riêng như `/chapters`, `/muc-luc`, `index.html`).
3. Mở chương đầu, tìm khung nội dung (thuật toán kiểu Readability: khối có nhiều chữ nhất, ít link).
4. Từ trang chủ: tìm tab (Mới cập nhật / Hot / Full / Latest / Completed...), thể loại, và form tìm kiếm.
   Search được xác nhận bằng cách tìm thử chính tên truyện mẫu.
5. Ghi extension: code runtime dùng chung cho mọi site (`runtime/*.js`), chỉ `src/config.js` là riêng.

## Cấu trúc extension

```
extensions/<domain>/
  plugin.zip       bản đóng gói để cài vào app (plugin.json, icon.png, src/ ở gốc zip)
  plugin.json      metadata + map script (home, genre, detail, search, toc, chap)
  icon.png         favicon của site
  src/config.js    selector riêng của site  ← chỉ cần sửa file này khi site đổi giao diện/domain
  src/lib.js       helper chung (phân trang, ảnh lazy-load, URL tương đối...)
  src/*.js         script theo chuẩn Vbook: execute(...) trả Response.success(...)
```

Runtime có fallback nhiều tầng: selector đã nhận diện → meta `og:*` → selector phổ biến
(`#chapter-c`, `.chapter-content`, `article`...). Phân trang dùng chung 1 cơ chế (rel=next → nút
"Next/Tiếp/»/下一页" → số trang active + 1), nên không cần cấu hình riêng.

## Giới hạn (cần biết)

Không tool nào đảm bảo 100% mọi site. Đã test pass đầy đủ: truyenfull, dtruyen/wetruyen,
readnovelfull, allnovelfull/novgo, novelfire; piaotia (GBK) đọc được nhưng thiếu Home/Search.
Các trường hợp tool **không** tự xử lý được — test sẽ báo ✘ kèm gợi ý:

- Site bị Cloudflare challenge / bắt đăng nhập.
- Nội dung hoặc danh sách chương render bằng JavaScript/AJAX (cần viết tay API call trong toc.js/chap.js).
- Search dùng POST hoặc site GBK cần encode từ khoá GBK.
- Nội dung chương bị mã hoá / chống copy.

Khi gặp ✘: mở `src/config.js`, sửa selector (CSS selector kiểu Jsoup), chạy `node cli.js test <thư-mục>`,
rồi `node cli.js pack <thư-mục>` để cập nhật plugin.zip.
Đặt `DEBUG=1` để xem từng request.
