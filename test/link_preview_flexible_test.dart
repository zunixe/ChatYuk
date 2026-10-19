import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/widgets/link_preview_image.dart';

void main() {
  group('linkPreviewImageHeight (tinggi mengikuti lebar kartu)', () {
    test('landscape 16:9 = lebar/1.78', () {
      expect(linkPreviewImageHeight(300, 16 / 9), closeTo(168.75, 0.01));
    });

    test('potret 9:16 = lebar*1.78', () {
      expect(linkPreviewImageHeight(300, 9 / 16), closeTo(533.33, 0.01));
    });

    test('kotak 1:1 = setinggi lebarnya', () {
      expect(linkPreviewImageHeight(300, 1.0), 300);
    });

    test('banner sangat lebar dibatasi tinggi minimum', () {
      expect(linkPreviewImageHeight(300, 5.0), 120);
    });

    test('rasio tak valid -> fallback 16:9', () {
      expect(linkPreviewImageHeight(300, 0), closeTo(168.75, 0.01));
      expect(
        linkPreviewImageHeight(300, double.infinity),
        closeTo(168.75, 0.01),
      );
      expect(linkPreviewImageHeight(300, double.nan), closeTo(168.75, 0.01));
    });
  });

  group('linkPreviewCardWidth (lebar adaptif konten ala WhatsApp)', () {
    test('foto potret → kartu lebih sempit dari lebar maksimum', () {
      // capH 260, rasio 0.786 (referensi WhatsApp 308x392) → 204.4
      expect(linkPreviewCardWidth(400, 0.786, 260), closeTo(204.36, 0.1));
    });

    test('Shorts 9:16 → kartu tetap wajar (min 160)', () {
      expect(linkPreviewCardWidth(400, 9 / 16, 260), 160);
    });

    test('landscape 16:9 → kartu penuh lebar maksimum', () {
      expect(linkPreviewCardWidth(400, 16 / 9, 260), 400);
    });

    test('rasio belum diketahui → lebar penuh', () {
      expect(linkPreviewCardWidth(400, null, 260), 400);
      expect(linkPreviewCardWidth(400, 0, 260), 400);
    });
  });
}
