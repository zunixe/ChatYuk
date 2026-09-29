/// Model + klasifikasi murni satu baris riwayat panggilan (halaman
/// "Panggilan Terbaru").
///
/// Sengaja BEBAS plugin & locale: parsing & penetapan arah/outcome dikunci
/// unit test, sedangkan teks tampilan dipetakan dari `S` di lapisan screen.
library;

/// Hasil akhir satu panggilan (untuk ikon & warna di daftar riwayat).
enum CallOutcome {
  /// Terjawab & selesai normal (durasi ditampilkan).
  completed,

  /// Tidak dijawab / dibatalkan penelepon sebelum diangkat.
  missed,

  /// Ditolak penerima.
  declined,

  /// Dibatalkan penelepon sebelum diangkat.
  canceled,

  /// Penerima sedang dalam panggilan lain.
  busy,

  /// Masih berlangsung (ringing/answered) — biasanya request basi.
  ongoing,
}

/// Satu baris riwayat panggilan dari tabel `calls`.
class CallHistoryEntry {
  final String id;

  /// Uid lawan bicara (di luar saya) — siap dipakai buka chat / re-dial.
  final String otherUid;

  /// True bila SAYA yang menelepon.
  final bool isOutgoing;
  final bool isVideo;
  final CallOutcome outcome;
  final DateTime at;

  /// Durasi bicara (detik). 0 bila tak pernah terjawab.
  final int durationSec;

  const CallHistoryEntry({
    required this.id,
    required this.otherUid,
    required this.isOutgoing,
    required this.isVideo,
    required this.outcome,
    required this.at,
    required this.durationSec,
  });

  /// True bila tampil "merah" (panggilan tidak terjawab yang masuk).
  bool get isMissedIncoming =>
      !isOutgoing &&
      (outcome == CallOutcome.missed || outcome == CallOutcome.canceled);

  bool get hasDuration =>
      outcome == CallOutcome.completed && durationSec > 0;

  /// Bangun dari baris `calls` + uid saya. Mengembalikan null bila baris
  /// tidak memuat pasangan partisipan yang jelas.
  static CallHistoryEntry? fromRow(Map<String, dynamic> row, String myUid) {
    final caller = row['caller_id'] as String?;
    final callee = row['callee_id'] as String?;
    if (caller == null || callee == null) return null;
    final isOutgoing = caller == myUid;
    final otherUid = isOutgoing ? callee : caller;
    if (otherUid.isEmpty || otherUid == myUid) return null;

    final status = (row['status'] as String?) ?? '';
    final at = _parse(row['created_at']) ??
        _parse(row['answered_at']) ??
        DateTime.now();
    final answeredAt = _parse(row['answered_at']);
    final endedAt = _parse(row['ended_at']);
    final duration = _durationSec(answeredAt, endedAt);

    return CallHistoryEntry(
      id: (row['id'] as String?) ?? '',
      otherUid: otherUid,
      isOutgoing: isOutgoing,
      isVideo: row['call_type'] == 'video',
      outcome: classifyOutcome(
        status: status,
        isOutgoing: isOutgoing,
        answered: answeredAt != null,
      ),
      at: at,
      durationSec: duration,
    );
  }

  /// Klasifikasi outcome dari status `calls` + arah. Murni (unit-testable).
  static CallOutcome classifyOutcome({
    required String status,
    required bool isOutgoing,
    required bool answered,
  }) {
    switch (status) {
      case 'ended':
      case 'failed':
        if (!answered) {
          // Berakhir tanpa pernah diangkat: penelepon membatalkan, atau
          // penerima tak menjawab. Dua-duanya "tidak terjawab".
          return isOutgoing ? CallOutcome.canceled : CallOutcome.missed;
        }
        return CallOutcome.completed;
      case 'missed':
        return CallOutcome.missed;
      case 'declined':
        return CallOutcome.declined;
      case 'canceled':
        return isOutgoing ? CallOutcome.canceled : CallOutcome.missed;
      case 'busy':
        return CallOutcome.busy;
      default:
        // ringing/answered → masih berlangsung.
        return CallOutcome.ongoing;
    }
  }

  static DateTime? _parse(Object? v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static int _durationSec(DateTime? answeredAt, DateTime? endedAt) {
    if (answeredAt == null || endedAt == null) return 0;
    final d = endedAt.difference(answeredAt).inSeconds;
    return d < 0 ? 0 : d;
  }
}
