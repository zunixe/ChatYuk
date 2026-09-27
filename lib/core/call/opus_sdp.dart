/// Helper SDP murni (tanpa WebRTC/Flutter) untuk panggilan suara.
///
/// Tujuan: menurunkan latency + menaikkan ketahanan suara di jaringan jelek
/// dengan cara menambahkan parameter Opus pada SDP, SEBELUM dikirim ke lawan
/// (offer) atau sebelum dipakai (answer).
///
/// Mengapa perlu: default WebRTC memakai Opus tanpa FEC/DTX dan `minptime=20`
/// (paket 20ms). Untuk panggilan suara:
/// - `minptime=10`  → paket 10ms, latency turun (~10ms lebih pendek per hop).
/// - `useinbandfec=1` → Forward Error Correction: packet loss tak bikin suara
///   putus/garpu (retransmit berkurang = latency lebih stabil).
/// - `usedtx=1` → saat lawan diam tak mengirim paket (hemat kuota; tidak
///   menambah latency, hanya meniadakan paket "diam").
/// - `maxaveragebitrate=32000` → cukup jernih untuk suara, hemat bandwidth.
/// - `stereo=0` → panggilan suara cukup mono.
library;

/// Baris fmtp Opus yang diinginkan; urutan stabil supaya output deterministik
/// (mudah dites & dibandingkan).
const _opusParams = <String>[
  'minptime=10',
  'useinbandfec=1',
  'usedtx=1',
  'stereo=0',
  'maxaveragebitrate=32000',
];

/// Regex baris `a=fmtp:<pt> <payload>` (payload bisa kosong).
final _fmtpRe = RegExp(r'^a=fmtp:(\d+)([ \t]*)(.*)$');

/// Regex baris `a=rtpmap:<pt> <encoding>/<clock>[/<channels>]`.
/// `[^/\s]+` (bukan `\S+`) supaya encoding BERHENTI di '/' — dulu `\S+`
/// rakus menelan "opus/48000" sehingga deteksi kodek Opus selalu gagal.
final _rtpmapRe = RegExp(r'^a=rtpmap:(\d+)\s+([^/\s]+)/(\d+)');

/// Terapkan preferensi Opus low-latency pada [sdp].
///
/// Idempoten: memanggil 2× menghasilkan string yang sama. Aman: SDP tanpa
/// Opus dikembalikan apa adanya (tidak mengubah kodek lain seperti
/// PCMU/PCMA/telephone-event) sehingga panggilan tetap bisa connect.
///
/// Strategi per baris (tidak mengubah urutan m-line):
/// - baris `a=rtpmap:<pt> opus/...` → catat <pt> sebagai Opus.
/// - baris `a=fmtp:<pt> ...` dengan <pt> Opus → tulis ulang parameternya
///   (buang duplikat key lama, pasang nilai dari [_opusParams]) + sisipkan
///   parameter non-Opus milik aplikasi lain (mis. `apt=`) tetap apa adanya.
/// - baris `a=fmtp:<pt>` yang datang SEBELUM rtpmap-nya (urutan tak lazim)
///   ditunda lalu dijahit setelah rtpmap Opus ditemukan.
String applyOpusLowLatencyPrefs(String sdp) {
  if (sdp.isEmpty) return sdp;
  final lines = sdp.split(RegExp(r'\r\n|\n|\r'));

  // 1) Kumpulkan payload-type (pt) yang Opus.
  final opusPts = <String>{};
  for (final line in lines) {
    final m = _rtpmapRe.firstMatch(line);
    if (m != null && m.group(2)!.toLowerCase() == 'opus') {
      opusPts.add(m.group(1)!);
    }
  }
  if (opusPts.isEmpty) return sdp; // tidak ada Opus → jangan sentuh.

  // 2) Bangun ulang baris fmtp Opus.
  var touched = false;
  final out = <String>[];
  for (final line in lines) {
    final m = _fmtpRe.firstMatch(line);
    if (m != null && opusPts.contains(m.group(1)!)) {
      final existing = _parseParams(m.group(3)!);
      final merged = _mergeParams(existing);
      out.add('a=fmtp:${m.group(1)} ${merged.join(';')}');
      touched = true;
      continue;
    }
    out.add(line);
  }
  if (!touched) {
    // Ada Opus tapi tanpa baris fmtp (lazimnya tidak terjadi) → tambahkan
    // tepat setelah baris rtpmap Opus pertama.
    final idx = out.indexWhere(
      (l) => _rtpmapRe.firstMatch(l)?.group(2)?.toLowerCase() == 'opus',
    );
    if (idx >= 0) {
      final pt = _rtpmapRe.firstMatch(out[idx])!.group(1)!;
      out.insert(idx + 1, 'a=fmtp:$pt ${_opusParams.join(';')}');
      touched = true;
    }
  }
  if (!touched) return sdp;

  // Pertahankan akhir baris asli: kalau input pakai CRLF, keluarkan CRLF.
  final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
  return out.join(eol);
}

/// Parse `k=v;k2=v2` → list pasangan; nilai kosong tetap dipertahankan
/// (mis. `apt=`), dan entri tanpa `=` (mis. flag) disimpan utuh.
List<String> _parseParams(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  return trimmed
      .split(';')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// Gabungkan parameter lama + preferensi kita. Kunci yang kita atur MENANG
/// (nilai lama untuk kunci yang sama dibuang supaya tidak duplikat), kunci
/// lain (mis. `apt=`) dipertahankan.
List<String> _mergeParams(List<String> existing) {
  final ours = <String, String>{};
  for (final p in _opusParams) {
    final i = p.indexOf('=');
    ours[p.substring(0, i)] = p.substring(i + 1);
  }
  final kept = <String>[];
  for (final p in existing) {
    final i = p.indexOf('=');
    final key = i < 0 ? p : p.substring(0, i);
    if (ours.containsKey(key)) continue; // akan diganti nilai kita
    kept.add(p);
  }
  return [..._opusParams, ...kept];
}
