import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/media/link_preview_service.dart';

/// Regresi: link hasil COPY-PASTE tanpa `https://` tetap dapat preview.
void main() {
  String? ex(String t) => LinkPreviewService.instance.extractUrl(t);

  test('https tetap jalan', () {
    expect(ex('cek https://youtu.be/abc oke'), 'https://youtu.be/abc');
  });

  test('www. tanpa skema', () {
    expect(ex('www.tokopedia.com/abc'), 'https://www.tokopedia.com/abc');
  });

  test('domain tanpa www & tanpa skema', () {
    expect(ex('lihat shopee.co.id/x'), 'https://shopee.co.id/x');
    expect(ex('kompas.com/berita/1'), 'https://kompas.com/berita/1');
  });

  test('tanda baca penutup dibuang', () {
    expect(ex('buka tokopedia.com/a.'), 'https://tokopedia.com/a');
    expect(ex('(lihat detik.com/x)'), 'https://detik.com/x');
  });

  test('bukan link: file.txt / versi / email', () {
    expect(ex('file.txt'), isNull);
    expect(ex('versi v1.2.3'), isNull);
    expect(ex('kirim ke user@mail.com'), isNull);
  });

  test('skema HURUF BESAR dinormalisasi', () {
    expect(ex('Https://s.shopee.co.id/abc'), 'https://s.shopee.co.id/abc');
  });

  test('cache gagal/tanpa judul TIDAK dipakai (harus re-fetch)', () {
    expect(
      LinkPreviewService.isUsableCachedPreview(const LinkPreviewData(
        url: 'https://x.com', title: 'X', ok: true)),
      isTrue,
    );
    expect(
      LinkPreviewService.isUsableCachedPreview(const LinkPreviewData(
        url: 'https://x.com', title: 'x.com', ok: false)),
      isFalse,
    );
    expect(
      LinkPreviewService.isUsableCachedPreview(const LinkPreviewData(
        url: 'https://x.com', title: '', ok: true)),
      isFalse,
    );
  });
}
