import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/media/link_preview_service.dart';

/// Regresi: teks pesan yang HANYA berisi URL harus dikenali walau skemanya
/// huruf besar ("Https://…"). Dulu `replaceAll(extractUrl(text), '')` gagal
/// (extractUrl menormalkan skema ke huruf kecil) → URL tetap tampil di bubble.
void main() {
  final svc = LinkPreviewService.instance;

  test('URL saja (https, huruf kecil) → true', () {
    expect(svc.isUrlOnly('https://youtube.com/shorts/abc'), isTrue);
  });

  test('URL saja dgn skema HURUF BESAR → true', () {
    expect(svc.isUrlOnly('Https://youtube.com/shorts/ouGI3w?si=O5pG'), isTrue);
  });

  test('URL saja tanpa skema → true', () {
    expect(svc.isUrlOnly('youtube.com/shorts/abc'), isTrue);
  });

  test('ada teks tambahan → false', () {
    expect(svc.isUrlOnly('cek https://tokopedia.com/a ya'), isFalse);
  });

  test('kalimat biasa → false', () {
    expect(svc.isUrlOnly('halo apa kabar hari ini'), isFalse);
  });

  test('spasi di sekitar URL → tetap true', () {
    expect(svc.isUrlOnly('  https://youtube.com/x  '), isTrue);
  });
}
