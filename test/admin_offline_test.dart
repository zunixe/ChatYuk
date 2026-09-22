import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/core/admin_err.dart';

/// Admin panel tahan offline:
///   1. Pesan exception MENTAH tidak boleh jadi teks yang tampil (bocorkan
///      URL project Supabase + membingungkan admin).
///   2. Kegagalan koneksi harus terklasifikasi `offline` supaya UI bisa
///      menampilkan banner "data terakhir", bukan layar error.
void main() {
  group('classifyAdminError', () {
    test('SocketException → offline', () {
      expect(
        classifyAdminError(const SocketException('Failed host lookup')),
        AdminErrKind.offline,
      );
    });

    test('pesan ClientException ber-URL Supabase → offline', () {
      // Bentuk asli yang dulu bocor ke layar.
      final e = Exception(
        "ClientException with SocketException: Failed host lookup: "
        "'fohcucyyejdryryoxitm.supabase.co' (OS Error: No address "
        'associated with hostname, errno = 7)',
      );
      expect(classifyAdminError(e), AdminErrKind.offline);
    });

    test('TimeoutException → offline', () {
      expect(classifyAdminError(TimeoutException('timeout')),
          AdminErrKind.offline);
    });

    test('PostgrestException Unauthorized → unauthorized (bukan offline)', () {
      expect(
        classifyAdminError(const PostgrestException(message: 'Unauthorized')),
        AdminErrKind.unauthorized,
      );
    });

    test('HttpException → server', () {
      expect(classifyAdminError(const HttpException('500')),
          AdminErrKind.server);
    });

    test('null / objek asing → unknown', () {
      expect(classifyAdminError(null), AdminErrKind.unknown);
      expect(classifyAdminError(StateError('boom')), AdminErrKind.unknown);
    });

    test('adminErrIsOffline helper', () {
      expect(adminErrIsOffline(AdminErrKind.offline), isTrue);
      expect(adminErrIsOffline(AdminErrKind.server), isFalse);
      expect(adminErrIsOffline(null), isFalse);
    });
  });

  group('blockIfOffline — guard aksi tulis admin', () {
    test('offline → diblokir + pesan terkirim', () {
      String? pesan;
      final blocked = blockIfOffline(
        false,
        (m) => pesan = m,
        message: 'Butuh koneksi internet',
      );
      expect(blocked, isTrue, reason: 'aksi harus diblokir saat offline');
      expect(pesan, 'Butuh koneksi internet');
    });

    test('online → tidak diblokir, tanpa pesan', () {
      var dipanggil = false;
      final blocked = blockIfOffline(
        true,
        (_) => dipanggil = true,
        message: 'Butuh koneksi internet',
      );
      expect(blocked, isFalse);
      expect(dipanggil, isFalse, reason: 'online = tidak ada pesan gangguan');
    });
  });
}
