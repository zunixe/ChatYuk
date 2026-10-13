import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/avatar_provider.dart';
import '../providers/riverpod/service_locator.dart';
import 'user_avatar.dart';

/// Avatar satu orang yang KONSISTEN di seluruh app.
///
/// Satu sumber kebenaran untuk: foto (base64 ATAU path), LATAR tint warna
/// GENDER, RING warna GENDER, dan (opsional) titik status presence. Semua
/// halaman user-facing (Pengguna Online, chat private + header, profil,
/// daftar Pesan, room, leaderboard) WAJIB memakai ini supaya orang yang SAMA
/// selalu punya warna+ring SAMA di mana pun ia muncul.
///
/// Aturan warna gender (sama dengan daftar Online):
///   male   → [AppTheme.male]   (biru)
///   female → [AppTheme.female] (merah muda)
///   lain   → [AppTheme.accent]
///
/// Ring gender HANYA tampil saat placeholder inisial (tanpa foto); foto
/// tampil bersih tanpa ring (regresi foto gelap bercacat).
class PersonAvatar extends StatefulWidget {
  final String uid;
  final String name;
  /// Gender mentah dari server ('male' / 'female' / lainnya).
  final String gender;
  /// Sumber avatar: base64 ATAU path storage `avatars/...`. Kosong = inisial.
  final String avatarB64;
  final double size;

  /// Titik status presence di kanan-bawah (mis. 'online'/'idle'/'offline').
  /// null = tanpa badge. Warna dari [AppTheme.statusColor].
  final String? status;

  /// Badge kustom menimpa [status] (mis. ikon blokir). Posisi kanan-bawah.
  final Widget? badge;

  const PersonAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.gender = '',
    this.avatarB64 = '',
    this.size = 40,
    this.status,
    this.badge,
  });

  /// Warna gender — satu-satunya sumber kebenaran.
  static Color colorFor(String gender) {
    switch (gender) {
      case 'male':
        return AppTheme.male;
      case 'female':
        return AppTheme.female;
      default:
        return AppTheme.accent;
    }
  }

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar> {
  /// Src efektif — kalau [PersonAvatar.avatarB64] kosong, resolve by-uid
  /// (RAM/disk/network via AvatarNotifier) supaya foto tetap tampil walau
  /// pemanggil hanya punya uid (mis. header chat private).
  String _src = '';

  /// Generasi resolve — melindungi retry tertunda dari uid yang sudah
  /// berganti (scroll cepat) supaya tak menimpa foto uid baru.
  int _resolveGen = 0;

  /// Timer retry tertunda — dibatalkan di dispose agar tak menggantung.
  Timer? _retryTimer;

  @override
  void dispose() {
    _resolveGen++;
    _retryTimer?.cancel();
    _retryTimer = null;
    super.dispose();
  }

  AvatarNotifier get _avatarSvc {
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(avatarProvider);
    } catch (_) {
      return AvatarNotifier(UiServices.avatar);
    }
  }

  @override
  void initState() {
    super.initState();
    _src = widget.avatarB64;
    // Fast-path SINKRON (RAM→disk) untuk frame pertama — list chat tak kirim
    // avatarB64 → dulu langsung async → frame-1 inisial (kedip/"kadang hilang").
    if (_src.isEmpty) {
      _src = _avatarSvc.cachedSync(widget.uid) ??
          _avatarSvc.cachedSyncIncludeDisk(widget.uid) ??
          '';
    }
    if (_src.isEmpty) _resolveUid();
  }

  @override
  void didUpdateWidget(PersonAvatar old) {
    super.didUpdateWidget(old);
    if (old.avatarB64 != widget.avatarB64) {
      _src = widget.avatarB64;
      if (_src.isEmpty) _resolveUid();
    } else if (old.uid != widget.uid && widget.avatarB64.isEmpty) {
      // ELEMENT DAUR-ULANG (ListView recycle): uid BARU. SINKRON dulu dari
      // RAM→disk supaya frame ini TIDAK kosong (dulu `_src=''` lalu async =
      // avatar hilang 1+ frame saat scroll = "kadang tampil kadang tidak").
      _src = _avatarSvc.cachedSync(widget.uid) ??
          _avatarSvc.cachedSyncIncludeDisk(widget.uid) ??
          '';
      if (_src.isEmpty) _resolveUid();
    }
  }

  Future<void> _resolveUid() async {
    if (widget.uid.isEmpty) return;
    final gen = ++_resolveGen;
    final uid = widget.uid;
    // Fast-path sinkron RAM: kalau sudah di RAM, tampil tanpa menunggu async.
    final sync = _avatarSvc.cachedSync(uid);
    if (sync != null && sync.isNotEmpty) {
      if (mounted && widget.uid == uid && gen == _resolveGen) {
        setState(() => _src = sync);
      }
      return;
    }
    // Fast-path sinkron RAM→DISK: byte avatar (MediaDiskCache) bertahan antar
    // sesi → frame pertama sudah foto. Tanpa ini, RAM-miss → async `get()` →
    // list chat "kadang tampil kadang tidak" (race). Disk-read sync murah
    // (file kecil per uid).
    final disk = _avatarSvc.cachedSyncIncludeDisk(uid);
    if (disk != null && disk.isNotEmpty) {
      if (mounted && widget.uid == uid && gen == _resolveGen) {
        setState(() => _src = disk);
      }
      return;
    }
    try {
      final b64 = await _avatarSvc.get(uid);
      if (!mounted || widget.uid != uid || gen != _resolveGen) return;
      if (b64.isNotEmpty) {
        setState(() => _src = b64);
        return;
      }
    } catch (_) {}
    // Sekali retry tertunda untuk kegagalan transien (mis. RPC timeout saat
    // boot storm): tanpa ini avatar gagal-sesaat "hilang" sampai widget
    // rebuild. Guard generasi + uid + _src kosong mencegah loop/timpa.
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () async {
      _retryTimer = null;
      if (!mounted || widget.uid != uid || gen != _resolveGen) return;
      if (_src.isNotEmpty) return;
      try {
        final b64 = await _avatarSvc.get(uid);
        if (!mounted || widget.uid != uid || gen != _resolveGen) return;
        if (b64.isNotEmpty) setState(() => _src = b64);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = PersonAvatar.colorFor(widget.gender);
    final initial =
        widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';

    final avatar = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
      ),
      clipBehavior: Clip.antiAlias,
      child: UserAvatar(
        key: ValueKey(widget.uid),
        uid: widget.uid,
        avatarB64: _src,
        initial: initial,
        color: color,
        borderColor: color,
        borderWidth: 1.5,
      ),
    );

    final showStatus = widget.badge == null &&
        widget.status != null &&
        widget.status!.isNotEmpty;
    if (widget.badge == null && !showStatus) return avatar;

    final dot = widget.size * 0.28; // ~11px untuk avatar 40px
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: widget.badge ??
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: AppTheme.statusColor(widget.status),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
        ),
      ],
    );
  }
}
