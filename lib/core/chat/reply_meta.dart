import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/strings.dart';
import '../../widgets/video_prefetch.dart';
import '../cache/photo_cache.dart';
import 'chat_location.dart';

/// Metadata KUTIPAN BALASAN (ala WhatsApp) — payload `reply_meta` yang
/// dikirim bersama `replied_to_text`/`replied_to_sender_name` dan disimpan
/// sebagai JSON di `replied_to_meta` (private_messages & messages).
///
/// Kenapa perlu: kutipan balasan dulu hanya menyimpan TEKS. Untuk pesan
/// media (foto/video/lokasi/dll) teksnya kosong → kotak kutipan tidak
/// muncul sama sekali, padahal WhatsApp menampilkan nama + ikon jenis +
/// THUMBNAIL kecil di sisi kanan bubble. Modul ini juga memutuskan kapan
/// thumbnail boleh dirender (lewat kunci cache lokal yang sama dengan
/// bubble aslinya).
///
/// Semua anggota statis murni (kecuali [thumb]) — aman diuji tanpa widget.

/// Jenis media yang dikenal di kutipan balasan.
enum ReplyMediaKind {
  photo,
  video,
  videoOnce,
  viewOnce,
  location,
  voice,
  sticker,
  file,
  contact,
  poll,
  gift,
  coin,
  call,
  text,
}

/// Map `type` pesan (MessageModel.type) → jenis kutipan.
ReplyMediaKind replyMediaKindOfType(String? type) {
  switch (type) {
    case 'image':
      return ReplyMediaKind.photo;
    case 'video':
      return ReplyMediaKind.video;
    case 'video_once':
    case 'video_once_expired':
      return ReplyMediaKind.videoOnce;
    case 'view_once':
    case 'view_once_expired':
      return ReplyMediaKind.viewOnce;
    case 'location':
      return ReplyMediaKind.location;
    case 'voice':
      return ReplyMediaKind.voice;
    case 'sticker':
      return ReplyMediaKind.sticker;
    case 'file':
      return ReplyMediaKind.file;
    case 'contact':
      return ReplyMediaKind.contact;
    case 'poll':
      return ReplyMediaKind.poll;
    case 'gift':
      return ReplyMediaKind.gift;
    case 'coin':
      return ReplyMediaKind.coin;
    case 'call':
      return ReplyMediaKind.call;
    default:
      return ReplyMediaKind.text;
  }
}

/// Ikon kecil di depan ringkasan teks kutipan (ala WhatsApp).
IconData? replyMediaIcon(ReplyMediaKind kind) {
  switch (kind) {
    case ReplyMediaKind.photo:
      return Icons.photo_outlined;
    case ReplyMediaKind.video:
    case ReplyMediaKind.videoOnce:
      return Icons.videocam_outlined;
    case ReplyMediaKind.viewOnce:
      return Icons.visibility_outlined;
    case ReplyMediaKind.location:
      return Icons.location_on_outlined;
    case ReplyMediaKind.voice:
      return Icons.mic_none;
    case ReplyMediaKind.sticker:
      return Icons.emoji_emotions_outlined;
    case ReplyMediaKind.file:
      return Icons.insert_drive_file_outlined;
    case ReplyMediaKind.contact:
      return Icons.person_outline;
    case ReplyMediaKind.poll:
      return Icons.poll_outlined;
    case ReplyMediaKind.gift:
      return Icons.card_giftcard;
    case ReplyMediaKind.coin:
      return Icons.monetization_on_outlined;
    case ReplyMediaKind.call:
      return Icons.call_outlined;
    case ReplyMediaKind.text:
      return null;
  }
}

/// Label bawaan bila tidak ada caption (dilokalkan via [S]).
String replyMediaFallbackLabel(ReplyMediaKind kind, S s) {
  switch (kind) {
    case ReplyMediaKind.photo:
      return s.msgPhoto;
    case ReplyMediaKind.video:
    case ReplyMediaKind.videoOnce:
      // Video sekali-lihat TIDAK punya thumbnail di kutipan (privasi) —
      // labelnya dibedakan agar penerima tidak bingung.
      return kind == ReplyMediaKind.videoOnce ? s.replyVideoOnce : s.previewVideo;
    case ReplyMediaKind.viewOnce:
      return s.replyPhotoOnce;
    case ReplyMediaKind.location:
      return s.msgLocation;
    case ReplyMediaKind.voice:
      return s.msgVoice;
    case ReplyMediaKind.sticker:
      return s.previewSticker;
    case ReplyMediaKind.file:
      return s.menuSendFile;
    case ReplyMediaKind.contact:
      return s.menuSendContact;
    case ReplyMediaKind.poll:
      return s.previewPoll;
    case ReplyMediaKind.gift:
      return s.previewGift;
    case ReplyMediaKind.coin:
      return s.previewCoin;
    case ReplyMediaKind.call:
      return s.msgCall;
    case ReplyMediaKind.text:
      return '';
  }
}

/// `reply_meta` yang dikirim penyimpan—hanya kunci yang tersedia.
///
/// Kunci:
/// - `t`  : type pesan asli (MessageModel.type)
/// - `id` : id pesan asli (string) — untuk lookup thumbnail lokal
/// - `w`,`h`: dimensi media (bila sudah diketahui pengirim) → rasio kotak
///            thumbnail di kutipan tanpa menunggu decode
/// - `p`  : path storage video (poster video di-resolve dari cache lokal
///          dengan kunci yang sama seperti bubble video)
/// - `d`  : chat key cache (mis. `private_<chatId>` / `room_<id>`) — dicatat
///          supaya thumbnail foto bisa diambil dari PhotoCache pesan asli
///
/// Null/kosong → kutipan hanya memakai teks (perilaku lama).
Map<String, dynamic> buildReplyMeta({
  String? type,
  String? messageId,
  int? width,
  int? height,
  String? videoPath,
  String? chatKey,
}) {
  final m = <String, dynamic>{};
  final t = (type ?? '').trim();
  if (t.isNotEmpty) m['t'] = t;
  final id = (messageId ?? '').trim();
  if (id.isNotEmpty) m['id'] = id;
  if (width != null && width > 0) m['w'] = width;
  if (height != null && height > 0) m['h'] = height;
  final vp = (videoPath ?? '').trim();
  if (vp.isNotEmpty && t.startsWith('video')) m['p'] = vp;
  final ck = (chatKey ?? '').trim();
  if (ck.isNotEmpty) m['d'] = ck;
  return m;
}

/// Kutipan balasan yang siap-dirender.
///
/// [rawText] adalah `replied_to_text` apa adanya (bisa JSON lokasi).
/// [isLocationPayload] text JSON lokasi dianggap lokasi walau `type` tak ada
/// (baris lama yang belum punya `replied_to_meta`).
class ReplyQuoteData {
  final ReplyMediaKind kind;
  final String? messageId;
  final String? senderName;
  final String text;
  final String cacheChatKey;
  final String videoPath;
  final double aspect;

  const ReplyQuoteData({
    required this.kind,
    this.messageId,
    this.senderName,
    this.text = '',
    this.cacheChatKey = '',
    this.videoPath = '',
    this.aspect = 0,
  });

  /// Ada isi yang bisa dikutip? (teks atau jenis media yang tampil eksplisit)
  bool get isEmpty => text.isEmpty && kind == ReplyMediaKind.text;
}

/// Susun data kutipan dari payload mentah.
///
/// [meta] = hasil decode `replied_to_meta` (null bila baris lama).
ReplyQuoteData? replyQuoteData({
  required String? repliedToText,
  required String? repliedToId,
  required String? repliedToSenderName,
  Map<String, dynamic>? meta,
}) {
  final type = meta?['t'] is String ? meta!['t'] as String : null;
  var kind = replyMediaKindOfType(type);
  final raw = (repliedToText ?? '').trim();
  // Baris lama tanpa meta: lokasi dikenali dari payload JSON-nya.
  if (kind == ReplyMediaKind.text && isLocationPayload(raw)) {
    kind = ReplyMediaKind.location;
  }
  final id = (meta?['id'] is String && (meta!['id'] as String).isNotEmpty)
      ? meta['id'] as String
      : repliedToId;
  final w = meta?['w'];
  final h = meta?['h'];
  final aspect = (w is num && h is num && w > 0 && h > 0)
      ? w / h
      : 0.0;
  final key = meta?['d'] is String ? meta!['d'] as String : '';
  final vp = meta?['p'] is String ? meta!['p'] as String : '';
  if (kind == ReplyMediaKind.text && raw.isEmpty) return null;
  return ReplyQuoteData(
    kind: kind,
    messageId: id,
    senderName: repliedToSenderName,
    text: raw,
    cacheChatKey: key,
    videoPath: vp,
    aspect: aspect.toDouble(),
  );
}

// ── Thumbnail kutipan ───────────────────────────────────────────────────────
//
// WhatsApp menampilkan thumbnail KECIL di sisi kanan kutipan balasan. Kita
// tidak menyimpan gambar tambahan di server: thumbnail diambil dari
//   • FOTO: `PhotoCache` pesan asli (chatKey + messageId) — file lokal sudah
//     ada karena bubble aslinya pernah tampil di layar ini.
//   • VIDEO: poster/thumbnail yang sama dengan kartu video
//     (`VideoPrefetch.posterBytesStable`) — dirujuk lewat path di `reply_meta`.
// Bila belum ada (pesan di luar layar / belum pernah diunduh), TIDAK
// mengunduh apa pun: kutipan tampil ikon + label saja (hemat kuota).

/// Cache bitmap thumbnail kutipan (bounded, LIFO evict) — menghindari
/// decode ulang tiap scroll. Kunci: `img:<chatKey>:<id>` / `vid:<path>`.
class ReplyThumbCache {
  ReplyThumbCache._();
  static final ReplyThumbCache instance = ReplyThumbCache._();

  static const int _cap = 40;
  final Map<String, ui.Image> _mem = {};

  ui.Image? get(String key) => _mem[key];

  void put(String key, ui.Image img) {
    // JANGAN dispose bitmap lama: bisa masih dipakai widget yang sedang
    // dirender (pola sama dengan VideoPrefetch._clearPosterImages). Cukup
    // lepas referensi → GC mengambilnya saat tak terpakai.
    _mem.remove(key);
    _mem[key] = img;
    while (_mem.length > _cap) {
      _mem.remove(_mem.keys.first);
    }
  }

  /// Dipakai saat logout/ganti akun (tak ada bubble aktif).
  void clear() {
    for (final img in _mem.values) {
      try {
        img.dispose();
      } catch (_) {}
    }
    _mem.clear();
  }
}

/// Decode base64 → bitmap KECIL (maks [maxPx] sisi panjang). Null bila gagal.
Future<ui.Image?> decodeReplyThumb(String b64, {int maxPx = 72}) async {
  if (b64.isEmpty) return null;
  try {
    final bytes = base64Decode(b64);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxPx,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Ambil bitmap thumbnail FOTO kutipan (async: baca cache lokal → decode).
/// Null = belum tersedia (kutipan pakai ikon saja).
Future<ui.Image?> loadReplyPhotoThumb({
  required String chatKey,
  required String messageId,
}) async {
  if (chatKey.isEmpty || messageId.isEmpty) return null;
  final key = 'img:$chatKey:$messageId';
  final hit = ReplyThumbCache.instance.get(key);
  if (hit != null) return hit;
  try {
    final b64 = await PhotoCache.instance.loadThumb(chatKey, messageId);
    if (b64 == null || b64.isEmpty) return null;
    final img = await decodeReplyThumb(b64);
    if (img != null) ReplyThumbCache.instance.put(key, img);
    return img;
  } catch (_) {
    return null;
  }
}

/// Bitmap thumbnail VIDEO kutipan — SINKRON (poster sudah di memori bila
/// kartu video pernah tampil). Dipisah dari [loadReplyPhotoThumb] karena
/// videonya tidak butuh dekripsi.
ui.Image? replyVideoThumbSync(String videoPath) {
  if (videoPath.isEmpty) return null;
  final key = 'vid:$videoPath';
  final hit = ReplyThumbCache.instance.get(key);
  if (hit != null) return hit;
  // Bitmap poster pool sudah di-decode saat kartu video tampil.
  final img = VideoPrefetch.posterImageSync(videoPath);
  if (img != null) {
    ReplyThumbCache.instance.put(key, img);
    return img;
  }
  return null;
}

/// Muat thumbnail VIDEO kutipan secara async (poster bytes → decode kecil).
/// Dipakai saat bitmap pool belum hangat.
Future<ui.Image?> loadReplyVideoThumb(String videoPath) async {
  if (videoPath.isEmpty) return null;
  final key = 'vid:$videoPath';
  final hit = ReplyThumbCache.instance.get(key);
  if (hit != null) return hit;
  final bytes = VideoPrefetch.posterBytesStable(videoPath);
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 72,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    ReplyThumbCache.instance.put(key, frame.image);
    return frame.image;
  } catch (_) {
    return null;
  }
}

