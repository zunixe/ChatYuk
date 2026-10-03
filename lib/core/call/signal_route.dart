/// Routing sinyal call 1:1 — logika MURNI (tanpa I/O) supaya bisa diuji
/// tanpa jaringan/realtime.
///
/// Latar: `call_signals` dulu menyimpan SEMUA sinyal (termasuk tiap ICE
/// candidate, puluhan per call) dan ikut publication realtime → boros write
/// DB + egress. Solusinya: pisahkan sinyal reliable (wajib replay) dari
/// ephemeral (boleh hilang, dipulihkan lewat re-sync).
///
/// Aturan:
/// - **Ephemeral** (broadcast, tanpa DB): hanya `candidate` — high-churn,
///   hilangnya ditoleransi karena re-sync offer/answer memicu tukar candidate
///   ulang (`CallSession._syncAll` + queue `_pendingCandidates`).
/// - **Reliable** (DB `call_signals`): `offer`, `answer`, `bye`, `camera`, dan
///   semua `watch_*` — WAJIB sampai (callee bisa masih ringing saat offer
///   dikirim, jadi butuh catch-up SELECT).
library;

/// Tipe sinyal yang dikirim ephemeral (broadcast, TIDAK ditulis ke DB).
///
/// ⚠️ SEMENTARA KOSONG (2026-10-05): uji 2-device menunjukkan candidate via
/// Realtime Broadcast TIDAK sampai ke peer (peer tak pernah menerima
/// `candidate`) → ICE menunggu 15 dtk lalu fallback all-candidates → call
/// "menghubungkan lama". Jalur Broadcast belum cukup andal untuk candidate.
/// Jalur DB (postgres_changes) sudah terbukti cepat & reliabel, jadi semua
/// sinyal kembali lewat DB.
///
/// Kode broadcast di `call_service.dart` & fungsi di file ini DIPERTAHANKAN
/// (dorman) supaya bisa diaktifkan kembali SETELAH broadcast diperbaiki &
/// diuji. Untuk mengaktifkan: masukkan 'candidate' ke set ini.
const Set<String> kEphemeralSignalTypes = <String>{};

/// True bila [type] boleh dikirim via broadcast ephemeral.
bool isEphemeralSignal(String type) => kEphemeralSignalTypes.contains(type);

/// Bangun payload broadcast untuk sinyal ephemeral. [seq] dipakai membuat
/// `bid` (broadcast id) unik per pesan — broadcast tidak punya id DB, jadi
/// CallSession butuh id sintetis untuk dedup (realtime bisa dobel dengan
/// broadcast saat channel baru subscribe).
Map<String, dynamic> buildEphemeralEnvelope({
  required String? fromUid,
  required String type,
  Map<String, dynamic>? payload,
  required int seq,
  required int micros,
}) {
  return {
    'from': fromUid,
    'type': type,
    'bid': '$micros-$seq',
    'payload': {...?payload},
  };
}

/// Terjemahkan payload broadcast masuk → bentuk sinyal yang sama dengan
/// sinyal DB ({id?, type, ...payload}). Mengembalikan null bila bukan sinyal
/// yang valid, atau bila berasal dari diri sendiri (jangan proses gema).
Map<String, dynamic>? decodeEphemeralEnvelope(
  Map<String, dynamic> msg, {
  required String? myUid,
}) {
  final data = (msg['payload'] as Map?)?.cast<String, dynamic>();
  if (data == null) return null;
  if (myUid != null && data['from'] == myUid) return null;
  final type = data['type'] as String?;
  if (type == null || type.isEmpty) return null;
  // Defense: broadcast hanya untuk tipe ephemeral yang dikenal.
  if (!isEphemeralSignal(type)) return null;
  final payload = (data['payload'] as Map?)?.cast<String, dynamic>() ?? {};
  final bid = data['bid']?.toString();
  return {
    if (bid != null) 'id': 'b-$bid',
    'type': type,
    ...payload,
  };
}
