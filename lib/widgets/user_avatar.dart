import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../core/cache/media_disk_cache.dart';
import '../core/media/native_image.dart';
import '../utils.dart';

/// Avatar user (berbasis FOTO) yang MODULAR untuk semua halaman user-facing:
/// daftar "Pengguna Online", monitor admin, detail user, leaderboard, dsb.
///
/// Dulu logika ini hidup INLINE di `online_users_screen.dart` (`_AsyncAvatar`
/// + 3 map global) sehingga halaman lain menyalin kode & menyimpang. Sekarang
/// di sini satu-satunya implementasi "avatar foto + anti-kedip".
///
/// Sumber bytes: `AvatarB64Service` (RAM → DISK → network, RPC ber-privacy
/// `avatar_for`/`avatars_for`). Nilai `avatarB64` yang dioper boleh berupa:
///   * base64 penuh, ATAU
///   * PATH storage `avatars/<uid>[_<millis>].jpg` (di-resolve via disk cache).
///
/// Anti-kedip dipertahankan (riwayat insiden foto hilang/kedip):
///   * `ImageProvider` instance STABIL per-uid → ImageCache hit, rebuild
///     berapa pun tidak menyentuh bitmap.
///   * decode base64 besar di isolate (`compute`) supaya scroll tidak jank.
///   * hasil decode basi (foto sudah berganti) DIBUANG, tidak menimpa.
///   * decode gagal TIDAK mengosongkan foto yang sudah tampil.
///
/// [borderColor] digambar HANYA saat placeholder inisial (tanpa foto) —
/// foto tampil bersih tanpa ring (regresi foto gelap bercacat biru).
class UserAvatar extends StatefulWidget {
  final String uid;
  /// Sumber avatar: base64 ATAU path storage `avatars/...`. Kosong = inisial.
  final String avatarB64;
  /// Huruf inisial fallback bila tidak ada foto.
  final String initial;
  /// Warna huruf inisial (dan warna ring bila [borderColor] null).
  final Color color;
  /// Ring warna — hanya muncul saat placeholder inisial.
  final Color? borderColor;
  final double borderWidth;

  /// Bila true, ring [borderColor] tetap digambar (transparan) saat FOTO
  /// tampil — beberapa kartu (mis. Nearby) memakai border transparan agar
  /// ukuran/bayangan konsisten antara inisial↔foto. Default false = gaya
  /// daftar online: foto tampil TANPA ring sama sekali.
  final bool keepRingForPhoto;

  /// Radius sudut bingkai (0 = lingkaran penuh). >0 = kotak rounded
  /// (mis. avatar di panel admin / kartu list). Default 0 (lingkaran).
  final double borderRadius;

  const UserAvatar({
    super.key,
    required this.uid,
    required this.avatarB64,
    required this.initial,
    required this.color,
    this.borderColor,
    this.borderWidth = 1.5,
    this.keepRingForPhoto = false,
    this.borderRadius = 0,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

// ── Cache bersama (module-level, lintas widget & halaman) ──────────────────
//
// Cache byte avatar per-UID GLOBAL — bertahan antar state/widget rebuild.
// Urutan list bisa berubah tiap event presence; tanpa cache global, state
// widget ter-recycle → decode ulang → inisial sebentar = kedip.
//
// SATU-SATUNYA penyimpan bytes ter-decode (single source of truth).
// Dulu ada 2 salinan lagi untuk bytes yang SAMA (`_avatarCache` src→bytes
// di sini + `_bytesCache` di ProfileAvatar) → foto yang sama ditahan 2-3×
// di memori native (Uint8List) → bloat ratusan MB + GC storm = lag progresif
// yang pulih setelah restart. Keduanya DIHAPUS; semua widget berbagi map ini.
final Map<String, Uint8List> _avatarBytesByUid = {};
final Map<String, String> _avatarLastSrcByUid = {};

// ImageProvider instance STABIL per-UID — dipisahkan total dari data
// pengguna online yang berganti-ganti tiap event presence. Bitmap di-decode
// SEKALI per foto; rebuild list berapapun tidak menyentuh bitmap.
//
// Di-CAP via ResizeImage (≤ [_avatarDecodePx]) — avatar di list hanya ~40px;
// tanpa cap, JPEG 1080px di-decode penuh (~4.6MB bitmap) padahal butuh 40px
// (~0.01MB). 20 kartu = ~92MB terbuang → penyebab utama memory spike/lag.
final Map<String, ImageProvider> _avatarImageByUid = {};

/// Lebar decode maksimum avatar di list (px). 96 = cukup untuk avatar 40px
/// di layar 2-3× DPI tanpa blur, ~25× lebih kecil dari decode full-res.
const int _avatarDecodePx = 96;

/// Bungkus MemoryImage dengan cap decode. Provider STABIL per-uid (instance
/// sama dipakai terus) supaya ImageCache hit & tidak kedip.
ImageProvider _cappedAvatarImage(Uint8List bytes) =>
    ResizeImage(MemoryImage(bytes), width: _avatarDecodePx);

/// Bersihkan seluruh cache avatar modul ini (dipanggil saat logout/ganti akun).
void clearAllAvatarCaches() {
  _avatarBytesByUid.clear();
  _avatarLastSrcByUid.clear();
  _avatarImageByUid.clear();
}

// Batas ukuran map avatar global — tanpa ini, 3 map tumbuh seumur sesi
// (1 entry per user yang pernah terlihat) → risiko memori besar di HP
// low-end saat sesi panjang. Evict FIFO (urutan insert) kalau lewat cap.
//
// 120 (dulu 200): bitmap sudah di-cap render via [_cappedAvatarImage], tapi
// `_avatarBytesByUid` menyimpan bytes MENTAH base64-decoded (ratusan KB/uid)
// untuk zoom. 120 × ~200KB ≈ 24MB — cukup untuk list & tetap ringan.
const _avatarMapCap = 120;

void _boundAvatarMap(Map<String, Object?> m) {
  while (m.length > _avatarMapCap) {
    m.remove(m.keys.first);
  }
}

/// Decode base64 avatar di isolate — B64 besar dari network tidak boleh
/// block UI thread saat scroll list.
class _UserAvatarState extends State<UserAvatar> {
  ImageProvider? _provider;
  String? _asyncResolvingFor;

  /// UID pendek untuk log — aman untuk uid kosong/pendek.
  String get _uid8 => widget.uid.length >= 8
      ? widget.uid.substring(0, 8)
      : widget.uid.isEmpty
      ? '-'
      : widget.uid;

  @override
  void initState() {
    super.initState();
    _resolve();
    // Tanpa Timer.periodic(300ms) per kartu: decode isolate & tulis disk
    // async yang mendarat setelah frame pertama di-resolve via didUpdateWidget
    // (provider notifyListeners → parent rebuild) ATAU callback .then pada
    // compute() di bawah. Hemat 1 timer per kartu dalam list panjang.
  }

  void _resolve() {
    final src = widget.avatarB64;
    // Batasi map global sebelum tulis baru — evict FIFO kalau lewat cap.
    // CATATAN: `_avatarLastSrcByUid` SENGAJA tidak di-evict. Map itu hanya
    // menyimpan string pendek (path/base64), tapi jadi kunci "sumber sama"
    // di bawah — kalau entry-nya terbuang saat list panjang, decode ulang
    // jalan percuma dan satu kegagalan decode sempat mengosongkan foto
    // (gejala "kadang ada kadang hilang").
    _boundAvatarMap(_avatarBytesByUid);
    _boundAvatarMap(_avatarImageByUid);
    // Sumber sama & provider sudah ada → nol pekerjaan (paling sering).
    if (src == _avatarLastSrcByUid[widget.uid] && _provider != null) {
      return;
    }
    // Fast-path EMPTY: user tanpa foto (src kosong) yang sudah pernah
    // diproses sebagai kosong → tak ada kerja (dulu tiap rebuild jatuh ke
    // cabang EMPTY + log, memicu 100+ resolve/detik saat storm transisi).
    if (src.isEmpty && _avatarLastSrcByUid[widget.uid] == '' && _provider == null) {
      return;
    }
    _avatarLastSrcByUid[widget.uid] = src;
    if (src.isEmpty) {
      // Kosong → pertahankan provider lama (jangan kedip ke inisial).
      dlog('[AVATAR] $_uid8 EMPTY keep-old=${_provider != null}');
      return;
    }
    // Sumber non-kosong dan BARU (atau provider hilang) → buang bytes +
    // provider lama milik uid ini. Maps per-uid di bawah memakai `??=` /
    // `putIfAbsent` yang tidak pernah menimpa — tanpa ini foto lama tersaji
    // selamanya: user ganti avatar tidak muncul di list online HP lain
    // sampai restart app (State kartu dipertahankan antar-reorder, jadi
    // inilah satu-satunya jalur update foto).
    final staleProvider = _avatarImageByUid.remove(widget.uid);
    _avatarBytesByUid.remove(widget.uid);
    _provider = null;
    if (staleProvider != null) {
      try {
        PaintingBinding.instance.imageCache.evict(staleProvider);
      } catch (_) {}
    }
    // PATH storage → baca bytes dari MEDIA DISK CACHE (instan, tanpa
    // network) → foto langsung tampil bahkan di mount pertama.
    if (src.startsWith('avatars/')) {
      final disk = MediaDiskCache.instance.readSync(src);
      if (disk != null && disk.isNotEmpty) {
        _avatarBytesByUid[widget.uid] ??= disk;
        _provider = _avatarImageByUid.putIfAbsent(
          widget.uid,
          () => _cappedAvatarImage(_avatarBytesByUid[widget.uid]!),
        );
        _boundAvatarMap(_avatarBytesByUid);
        _boundAvatarMap(_avatarImageByUid);
      }
      // Tidak ada di disk → biarkan inisial; batch network akan mengisi.
      return;
    }
    // Instance MemoryImage stabil per-uid → pakai apa adanya.
    final stable = _avatarImageByUid[widget.uid];
    if (stable != null && _provider != stable) {
      _provider = stable;
      return;
    }
    // Decode sinkron (murah — server sudah q70/300px) lalu simpan
    // instance ImageProvider sekali selamanya untuk uid ini.
    // Bytes disimpan HANYA di `_avatarBytesByUid` (single source) — dulu ada
    // salinan kedua per-src (`_avatarCache`) yang menggandakan retensi.
    if (_avatarBytesByUid[widget.uid] == null) {
      Uint8List? b;
      if (src.length > 100000 && _asyncResolvingFor != src) {
        // B64 besar dari network batch → decode di isolate agar scroll
        // tidak jank; poll initState menampilkan hasilnya saat siap.
        _asyncResolvingFor = src;
        NativeImage.decodeBytes(src).then((decoded) {
          _asyncResolvingFor = null;
          if (decoded == null || decoded.isEmpty) {
            dlog(
              '[AVATAR] $_uid8 DECODE-FAIL(async) keep-old=${_provider != null}',
            );
            return;
          }
          // Foto sudah berganti saat decode berjalan → buang hasil basi
          // (jangan timpa foto baru dengan foto lama).
          if (_avatarLastSrcByUid[widget.uid] != src) {
            dlog('[AVATAR] $_uid8 STALE-DECODE dropped');
            return;
          }
          _avatarBytesByUid[widget.uid] ??= decoded;
          _avatarImageByUid.putIfAbsent(
            widget.uid,
            () => _cappedAvatarImage(_avatarBytesByUid[widget.uid]!),
          );
          _boundAvatarMap(_avatarBytesByUid);
          _boundAvatarMap(_avatarImageByUid);
          if (mounted) {
            setState(() => _provider = _avatarImageByUid[widget.uid]);
          }
        });
        return;
      } else if (src.length > 100000) {
        return;
      } else {
        try {
          b = base64Decode(src);
        } catch (_) {
          b = null;
        }
      }
      if (b == null) {
        // ── JANGAN buang foto yang sudah tampil ──
        // Satu emission dengan base64 rusak/kecil tidak boleh mengosongkan
        // kartu: pertahankan `_provider` lama dan tunggu emission berikutnya
        // membawa data benar. Dulu `_provider = null` di sini → foto hilang
        // (transparan) sampai batch network menyusul = "kadang ada kadang
        // hilang".
        dlog(
          '[AVATAR] $_uid8 DECODE-FAIL(sync) len=${src.length} '
          'keep-old=${_provider != null}',
        );
        return;
      }
      _avatarBytesByUid[widget.uid] = b;
    }
    _provider = _avatarImageByUid.putIfAbsent(
      widget.uid,
      () => _cappedAvatarImage(_avatarBytesByUid[widget.uid]!),
    );
    _boundAvatarMap(_avatarBytesByUid);
    _boundAvatarMap(_avatarImageByUid);
  }

  @override
  void didUpdateWidget(covariant UserAvatar old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  /// Circle tanpa radius; radius>0 → kotak rounded.
  bool get _isCircle => widget.borderRadius == 0;

  @override
  Widget build(BuildContext context) {
    _resolve();
    final p = _provider;
    if (p == null) {
      // Avatar ADA (PATH/B64) tapi bytes belum siap → TRANSPARAN, jangan
      // tampilkan huruf inisial dulu (user tidak mau flash "S" → foto).
      // Huruf hanya untuk yang memang tidak punya foto (string kosong).
      if (widget.avatarB64.isNotEmpty) {
        return const SizedBox.shrink();
      }
      final letter = Center(
        child: Text(
          widget.initial,
          style: TextStyle(
            color: widget.color,
            fontSize: AppGlyph.avatarInitial(40),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      // Placeholder inisial: pakai ring kalau diminta. Foto/loading:
      // tanpa ring supaya foto gelap tidak terlihat bercacat biru.
      if (widget.borderColor == null) return letter;
      return Container(
        decoration: BoxDecoration(
          shape: _isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: _isCircle
              ? null
              : BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: widget.borderColor!,
            width: widget.borderWidth,
          ),
        ),
        child: letter,
      );
    }
    // gaplessPlayback: foto benar-benar baru (bytes beda) → bitmap lama
    // tetap tampil sampai bitmap baru siap, tanpa blank putih.
    final photo = Image(
      image: p,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          widget.initial,
          style: TextStyle(
            color: widget.color,
            fontSize: AppGlyph.avatarInitial(40),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    // Kartu ala Nearby memakai border transparan saat foto tampil supaya
    // ukuran/geometri identik dengan placeholder inisial (ring "disamarkan,
    // bukan dihapus").
    if (widget.keepRingForPhoto && widget.borderColor != null) {
      return Container(
        decoration: BoxDecoration(
          shape: _isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: _isCircle
              ? null
              : BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: Colors.transparent,
            width: widget.borderWidth,
          ),
        ),
        // WAJIB clip: `BoxShape.circle` hanya membentuk border, BUKAN
        // memotong child. Tanpa ini, foto persegi menonjol keluar border →
        // tampak "background kotak" padahal border-nya bulat (mis. avatar di
        // sheet "Status kamu"). ClipOval untuk bulat, ClipRRect untuk kotak
        // rounded — jaga sudut tetap sesuai `borderRadius`.
        clipBehavior: Clip.antiAlias,
        child: _isCircle
            ? photo
            : ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: photo,
              ),
      );
    }
    // Foto BULAT tanpa ring → tetap clip (jangan biarkan persegi menonjol
    // bila pemanggil lupa membungkusnya ClipOval).
    if (_isCircle) {
      return ClipOval(child: photo);
    }
    return photo;
  }
}

/// Helper: bytes avatar (mentah base64-decoded) untuk uid tertentu bila sudah
/// ada di cache render modul ini — dipakai fitur zoom (layar online/admin)
/// dan `ProfileAvatar` (agar tidak menyimpan salinan bytes sendiri).
Uint8List? cachedUserAvatarBytes(String uid) => _avatarBytesByUid[uid];

/// Simpan bytes ter-decode ke cache bersama (bounded via [_boundAvatarMap]).
/// Dipakai `ProfileAvatar` agar bytes yang SAMA tidak ditahan 2× (dulu
/// `_bytesCache` 60 entri di sana + map di sini = retensi ganda native).
void rememberAvatarBytes(String uid, Uint8List bytes) {
  if (uid.isEmpty || bytes.isEmpty) return;
  _avatarBytesByUid[uid] ??= bytes;
  _boundAvatarMap(_avatarBytesByUid);
}
