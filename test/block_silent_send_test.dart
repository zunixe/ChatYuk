import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLOKIR SENYAP (keputusan produk 2026-10-23).
///
/// Orang yang diblokir TIDAK boleh tahu dirinya diblokir:
/// - Tidak ada snackbar "Anda diblokir" / "tidak bisa mengirim" saat kirim.
/// - Tidak ada pre-check blokir yang membatalkan kirim (bubble tak muncul).
/// - Pesan tetap tampil optimistis (centang-1) dan DITOLAK server → centang
///   tetap 1 (tanda tidak terkirim), bubble tidak dihapus.
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('private sendPreCheck tidak cek blokir & tanpa snackbar', () {
    final src = read('lib/screens/private_chat/private_chat_build.dart');
    final start = src.indexOf('Future<bool> sendPreCheck()');
    expect(start, greaterThan(-1), reason: 'sendPreCheck harus ada');
    // Ambil badan fungsi (sampai 400 char setelahnya, cukup untuk blok ini).
    final body = src.substring(start, (start + 700).clamp(0, src.length));
    expect(body.contains('chatBlockState'), isFalse,
        reason: 'pre-check RPC blokir harus dihapus (biar senyap)');
    expect(body.contains('msgBlocked'), isFalse,
        reason: 'tanpa snackbar blokir');
    expect(body.contains('return true'), isTrue,
        reason: 'selalu lanjut supaya bubble optimistis tampil');
  });

  test('ChatSendMixin: gagal blokir = tanpa snackbar, bubble tetap', () {
    final src = read('lib/mixins/chat_send_mixin.dart');
    expect(src.contains('isSilentBlock(e)'), isTrue);
    // Blokir ditangani cabang TERPISAH (bukan di dalam snackbar).
    expect(src.contains('msgBlockedByOther'), isFalse,
        reason: 'snackbar blokir harus hilang dari jalur kirim teks');
    final idx = src.indexOf('isSilentBlock(e)');
    final branch = src.substring(idx, (idx + 420).clamp(0, src.length));
    expect(branch.contains('outboxPending.remove'), isFalse,
        reason: 'bubble tidak boleh dihapus saat blokir (tetap centang-1)');
  });

  test('foto & video: gagal blokir juga tanpa snackbar, bubble tetap', () {
    final src = read('lib/mixins/chat_photo_send_mixin.dart');
    final n = 'isSilentBlock(e)'.allMatches(src).length;
    expect(n, greaterThanOrEqualTo(2),
        reason: 'jalur foto & video masing-masing menangani blokir');
  });

  test('menu header: blokir di-await, ada unblock, gagal tidak bohong', () {
    final src = read('lib/screens/private_chat/private_chat_core.dart');
    // Blokir WAJIB di-await — fire-and-forget membuat snackbar "sudah
    // diblokir" muncul walau INSERT gagal.
    expect(src.contains('await chat.blockUser('), isTrue,
        reason: 'blockUser harus di-await agar kegagalan terdeteksi');
    expect(src.contains('await chat.unblockUser('), isTrue,
        reason: 'menu harus bisa membuka blokir');
    // Menu toggle: label & aksi mengikuti status blokir.
    expect(src.contains("value: isBlocked ? 'unblock' : 'block'"), isTrue);
    expect(src.contains('s.btnUnblock'), isTrue);
    // Gagal → pesan error jujur, bukan "berhasil diblokir".
    expect(src.contains('s.snackBlocked(widget.otherName)'), isTrue);
    expect(src.contains("[BLOCK] GAGAL"), isTrue,
        reason: 'kegagalan blokir harus tercatat/ditangani');
    expect(src.contains("[BLOCK] unblock ok"), isTrue,
        reason: 'keberhasilan unblock tercatat');
  });
}
