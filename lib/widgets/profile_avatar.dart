import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../core/media/native_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/avatar_provider.dart';
import 'user_avatar.dart' show cachedUserAvatarBytes, rememberAvatarBytes;

Uint8List? _decodeAvatarB64(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

/// Avatar profil user lain: foto (base64, decode async + cache) dengan
/// fallback inisial. Lingkaran jika [borderRadius] = 0, atau kotak rounded.
///
/// [bgColor] null → `AppTheme.avatarBg` (solid, seragam dengan kartu list
/// Pesan & header chat). Dulu default `AppTheme.accent` (cyan pekat) sehingga
/// 15 dari 17 pemanggil yang tidak menyetel warna tampil beda dari daftar chat.
class ProfileAvatar extends StatefulWidget {
  final String uid;
  final String name;
  final double size;
  final double borderRadius;
  final Color? bgColor;
  final Color? textColor;
  final Color? borderColor;
  final double borderWidth;
  final Widget? badge;

  const ProfileAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.size = 44,
    this.borderRadius = 0,
    this.bgColor,
    this.textColor,
    this.borderColor,
    this.borderWidth = 1.5,
    this.badge,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _bytes;

  /// Akses avatar service lewat provider (boundary Fase B: widgets dilarang
  /// import services/ langsung). Fallback container → aman di test tanpa scope.
  AvatarNotifier get _avatarSvc =>
      ProviderScope.containerOf(context, listen: false).read(avatarProvider);

  @override
  void initState() {
    super.initState();
    _applySyncCache();
    _load();
  }

  /// Fast-path SINKRON: kalau base64 sudah ada di RAM (mis. dibuka dari
  /// daftar chat lalu masuk profil), tampilkan pada frame pertama tanpa
  /// menunggu compute/get async — anti-kedip.
  ///
  /// Bytes dibaca/ditulis ke cache BERSAMA `UserAvatar` (per-uid) — dulu
  /// widget ini menyimpan salinan sendiri (`_bytesCache` 60 entri) sehingga
  /// foto yang sama ditahan 2× di memori native.
  void _applySyncCache() {
    final shared = cachedUserAvatarBytes(widget.uid);
    if (shared != null) {
      _bytes = shared;
      return;
    }
    final ram = _avatarSvc.cachedSync(widget.uid);
    if (ram == null) return;
    final decoded = _decodeAvatarB64(ram);
    if (decoded != null) {
      rememberAvatarBytes(widget.uid, decoded);
      _bytes = decoded;
    }
  }

  @override
  void didUpdateWidget(ProfileAvatar old) {
    super.didUpdateWidget(old);
    // PENTING (anti "foto user sebelumnya"): ListView mendaur-ulang element
    // yang sama untuk uid BERBEDA tanpa memanggil initState. Tanpa cabang ini,
    // `_bytes` masih foto uid LAMA → sempat tampil foto salah (mis. user lain)
    // sampai _load() selesai.
    if (old.uid != widget.uid) {
      _bytes = null;
      _applySyncCache();
      _load();
    }
  }

  Future<void> _load() async {
    // Kunci uid saat mulai — hasil async hanya boleh dipakai bila uid belum
    // berubah (element didaur-ulang), supaya tidak menimpa dengan foto lama.
    final uid = widget.uid;
    // Retry bila hasil kosong — fetch serentak untuk uid yang sama
    // mengembalikan '' (inflight) dan widget ini tidak boleh menyerah
    // (kalau tidak, avatar stuck inisial sampai rebuild = kedip).
    // 3× (dulu 10×) — cukup untuk inflight race tanpa membebani list.
    for (var attempt = 0; attempt < 3; attempt++) {
      final b64 = await _avatarSvc.get(uid);
      if (!mounted || widget.uid != uid) return;
      if (b64.isNotEmpty) {
        final cached = cachedUserAvatarBytes(uid);
        if (cached != null) {
          setState(() => _bytes = cached);
          return;
        }
        final bytes = await NativeImage.decodeAvatar(b64, maxPx: 256);
        if (!mounted || widget.uid != uid || bytes == null) return;
        rememberAvatarBytes(uid, bytes);
        setState(() => _bytes = bytes);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCircle = widget.borderRadius == 0;
    final shape = BorderRadius.circular(widget.borderRadius);
    Widget child;
    if (_bytes != null) {
      final img = Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        // Avatar kecil (size x density ~2) — cap decode supaya tidak
        // raster gambar profil penuh untuk kotak mungil di daftar.
        cacheWidth: (widget.size * 2).round(),
        gaplessPlayback: true,
      );
      child = isCircle
          ? ClipOval(child: img)
          : ClipRRect(borderRadius: shape, child: img);
    } else {
      child = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.bgColor ?? AppTheme.avatarBg,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : shape,
        ),
        child: Center(
          child: Text(
            widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: widget.textColor ?? AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppGlyph.avatarInitial(widget.size),
            ),
          ),
        ),
      );
    }
    if (widget.borderColor != null && _bytes == null) {
      // Ring warna HANYA untuk placeholder inisial (tanpa foto). Digambar
      // DI DALAM bounds (foregroundDecoration) supaya ukuran total tetap
      // `size` — sama persis dengan daftar "Pengguna Online" (UserAvatar).
      //
      // Dulu ring memakai container `size + borderWidth*2` (membesar 3px)
      // → ring tampak "beda/kurang rapi" dibanding online dan bisa terpotong
      // bila dibungkus container ukuran tetap. Sekarang ring di dalam.
      child = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.bgColor ?? AppTheme.avatarBg,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : shape,
        ),
        foregroundDecoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : shape,
          border: Border.all(color: widget.borderColor!, width: widget.borderWidth),
        ),
        child: Center(
          child: Text(
            widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
            style: TextStyle(
              color: widget.textColor ?? AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppGlyph.avatarInitial(widget.size),
            ),
          ),
        ),
      );
    }
    if (widget.badge == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (widget.badge != null)
          Positioned(right: 0, bottom: 0, child: widget.badge!),
      ],
    );
  }
}
