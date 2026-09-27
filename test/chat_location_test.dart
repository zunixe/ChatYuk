import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_location.dart';

void main() {
  group('ChatLocation.encode / parseLocation', () {
    test('roundtrip koordinat + label + caption', () {
      const loc = ChatLocation(
        lat: -6.2,
        lng: 106.8,
        label: 'Monas',
        caption: 'Ketemuan di sini',
      );
      final parsed = parseLocation(loc.encode());
      expect(parsed, isNotNull);
      expect(parsed!.lat, closeTo(-6.2, 1e-9));
      expect(parsed.lng, closeTo(106.8, 1e-9));
      expect(parsed.label, 'Monas');
      expect(parsed.caption, 'Ketemuan di sini');
    });

    test('tanpa label → encode tidak menyertakan key label', () {
      const loc = ChatLocation(lat: 1.5, lng: 2.5);
      final json = jsonDecode(loc.encode()) as Map;
      expect(json.containsKey('label'), isFalse);
      expect(parseLocation(loc.encode())!.label, '');
    });

    test('mapsUrl pakai lat,lng', () {
      const loc = ChatLocation(lat: 1.5, lng: 2.5);
      expect(loc.mapsUrl, contains('query=1.5,2.5'));
    });

    test('roundtrip tempat + akurasi', () {
      const loc = ChatLocation(
        lat: -6.2,
        lng: 106.8,
        label: 'Jl. Mukodar Tengah, Cimahi',
        place: 'Masjid Al Ikhlas',
        accuracyM: 4,
      );
      final p = parseLocation(loc.encode())!;
      expect(p.place, 'Masjid Al Ikhlas');
      expect(p.accuracyM, 4);
      expect(p.live, isFalse);
      expect(p.expiresAt, isNull);
    });

    test('roundtrip lokasi live + expiresAt', () {
      final exp = DateTime.utc(2026, 1, 1, 10, 0);
      final loc = ChatLocation(
        lat: -6.2,
        lng: 106.8,
        live: true,
        expiresAt: exp,
      );
      final p = parseLocation(loc.encode())!;
      expect(p.live, isTrue);
      expect(p.expiresAt, exp);
      expect(p.isLiveActive, isFalse, reason: 'exp sudah lewat');
    });

    test('isLiveActive true bila belum kedaluwarsa', () {
      final loc = ChatLocation(
        lat: 1,
        lng: 2,
        live: true,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );
      expect(loc.isLiveActive, isTrue);
    });

    test('copyWith pertahankan live/expiresAt', () {
      final loc = ChatLocation(
        lat: 1,
        lng: 2,
        live: true,
        place: 'Kafe',
        expiresAt: DateTime.utc(2027),
      );
      final u = loc.copyWith(lat: 5, lng: 6);
      expect(u.lat, 5);
      expect(u.lng, 6);
      expect(u.live, isTrue);
      expect(u.place, 'Kafe');
      expect(u.expiresAt, DateTime.utc(2027));
    });
  });

  group('parseLocation — input tidak valid', () {
    test('teks biasa → null', () {
      expect(parseLocation('halo dunia'), isNull);
      expect(parseLocation(''), isNull);
      expect(parseLocation(null), isNull);
    });

    test('JSON tanpa lat/lng → null', () {
      expect(parseLocation('{"foo":"bar"}'), isNull);
    });

    test('JSON dengan lat/lng bukan angka → null', () {
      expect(parseLocation('{"lat":"a","lng":"b"}'), isNull);
    });

    test('koordinat di luar rentang → null', () {
      expect(parseLocation('{"lat":200,"lng":10}'), isNull);
      expect(parseLocation('{"lat":10,"lng":999}'), isNull);
    });

    test('label bukan string → jadi string kosong', () {
      final loc = parseLocation('{"lat":1,"lng":2,"label":123}');
      expect(loc, isNotNull);
      expect(loc!.label, '');
    });
  });

  group('isLocationPayload', () {
    test('true hanya untuk payload lokasi valid', () {
      expect(isLocationPayload(const ChatLocation(lat: 1, lng: 2).encode()),
          isTrue);
      expect(isLocationPayload('{"a":1}'), isFalse);
      expect(isLocationPayload('pesan biasa'), isFalse);
      expect(isLocationPayload(null), isFalse);
    });
  });

  group('locationPreviewLabel', () {
    test('pakai caption bila ada (di atas label)', () {
      final t = const ChatLocation(
        lat: 1,
        lng: 2,
        label: 'Rumah',
        caption: 'Lagi di sini',
      ).encode();
      expect(locationPreviewLabel(t, '[Lokasi]'), 'Lagi di sini');
    });

    test('pakai label bila ada', () {
      final t = const ChatLocation(lat: 1, lng: 2, label: 'Rumah').encode();
      expect(locationPreviewLabel(t, '[Lokasi]'), 'Rumah');
    });

    test('fallback bila tidak ada label', () {
      final t = const ChatLocation(lat: 1, lng: 2).encode();
      expect(locationPreviewLabel(t, '[Lokasi]'), '[Lokasi]');
    });

    test('fallback untuk teks biasa', () {
      expect(locationPreviewLabel('halo', '[Lokasi]'), '[Lokasi]');
    });
  });
}
