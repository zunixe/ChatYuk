import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/social_provider.dart';
import '../../../widgets/app_gesture.dart';
import '../../../widgets/person_avatar.dart';
import '../../../widgets/social_actions.dart';
import '../../../widgets/social_counts_line.dart';
import '../../../widgets/verified_badge.dart';

/// Kartu baris user di daftar "Pengguna Online".
///
/// Semua interaksi (tap, avatar, long-press, unhide) lewat callback —
/// tidak ada akses langsung ke state layar pemanggil.
class UserCard extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onTap;
  final void Function(Color avatarColor) onAvatarTap;
  // Dipanggil saat long-press: kirim titik jari + RECT kartu (global) supaya
  // bubble pesan-terakhir bisa nempel di ujung kartu (atas/bawah).
  final void Function(Offset globalPos, Rect cardRect)? onLongPress;
  final int unreadCount;
  final VoidCallback? onUnhide;
  const UserCard({
    super.key,
    required this.user,
    required this.onTap,
    required this.onAvatarTap,
    this.onLongPress,
    this.unreadCount = 0,
    this.onUnhide,
  });

  @override
  ConsumerState<UserCard> createState() => _UserCardState();
}

class _UserCardState extends ConsumerState<UserCard> {
  // Key pada Container kartu → currentContext.findRenderObject() = RECT kartu
  // yang SEBENARNYA (bukan ancestor RenderObject saat pakai Builder).
  final GlobalKey _cardKey = GlobalKey();

  UserModel get user => widget.user;
  VoidCallback get onTap => widget.onTap;
  void Function(Color) get onAvatarTap => widget.onAvatarTap;
  int get unreadCount => widget.unreadCount;
  VoidCallback? get onUnhide => widget.onUnhide;

  Color _statusColor(String status) => AppTheme.statusColor(status);

  // DateFormat dibuat SEKALI (statis) — dulu `DateFormat('d MMM')` bikin
  // objek baru tiap build kartu user idle >7 hari → pemborosan saat scroll.
  static final DateFormat _dayMonthFmt = DateFormat('d MMM');

  String _idleDurationLabel(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen.toLocal());
    if (diff.inMinutes < 1) return '1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return _dayMonthFmt.format(lastSeen.toLocal());
  }

  void _handleLongPress(LongPressStartDetails d) {
    final cb = widget.onLongPress;
    if (cb == null) return;
    final ro = _cardKey.currentContext?.findRenderObject();
    Rect rect;
    if (ro is RenderBox && ro.hasSize) {
      final tl = ro.localToGlobal(Offset.zero);
      rect = Rect.fromLTWH(tl.dx, tl.dy, ro.size.width, ro.size.height);
    } else {
      // Fallback: tak bisa ukur kartu → pakai titik jari saja.
      rect = Rect.fromCenter(center: d.globalPosition, width: 0, height: 0);
    }
    cb(d.globalPosition, rect);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final color = user.gender == 'male'
        ? AppTheme.male
        : user.gender == 'female'
        ? AppTheme.female
        : AppTheme.accent;
    final genderLabel = user.gender == 'male'
        ? s.genderMale
        : user.gender == 'female'
        ? s.genderFemale
        : s.genderOther;
    // Hanya 'online' yang berlabel Online — 'invisible'/lainnya = offline.
    // Dulu else-default ke Online sehingga baris invisible yang lolos
    // filter (mis. cache basi) tampil "Online" walau dot-nya abu-abu.
    final statusLabel = user.status == 'online'
        ? s.statusOnline
        : user.status == 'idle'
        ? '${s.statusIdle} · ${_idleDurationLabel(user.lastSeen)}'
        : s.statusOffline;

    return AppGestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPressStart: widget.onLongPress == null ? null : _handleLongPress,
      child: Container(
        key: _cardKey,
        margin: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        // Tanpa onTap di level kartu: 3 zona punya handler sendiri
        // (avatar→zoom, username→profil, ikon chat→chat).
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => onAvatarTap(color),
                    // PersonAvatar: satu-satunya sumber bentuk avatar orang
                    // (foto + tint & ring WARNA GENDER + titik presence) —
                    // SAMA PERSIS dengan header chat, profil, dll.
                    child: PersonAvatar(
                      uid: user.uid,
                      name: user.nickname,
                      gender: user.gender,
                      avatarB64: user.avatar,
                      size: 40,
                      status: user.status,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: AppText.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onTap,
                            child: Text(
                              user.nickname,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (user.gender == 'male' ||
                            user.gender == 'female') ...[
                          SizedBox(width: 4),
                          Icon(
                            user.gender == 'male' ? Icons.male : Icons.female,
                            size: 15,
                            color: user.gender == 'male'
                                ? AppTheme.male
                                : AppTheme.female,
                          ),
                        ],
                        if (user.isRegistered) ...[
                          SizedBox(width: 4),
                          VerifiedBadgeForUid(
                            uid: user.uid,
                            size: 15,
                            tooltip: s.phoneVerifiedBadge,
                          ),
                        ],
                      ],
                    ),
                    GestureDetector(
                      onTap: onTap,
                      child: Text(
                        '$genderLabel ${user.age} · ${user.city}, ${user.country}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Isi Tentang (dari RPC online, hormati about_visibility
                    // di server). Kosong = tidak tampil agar kartu ringkas.
                    // TANPA maxLines/ellipsis: teks "Tentang" tampil UTUH
                    // (dulu dipotong 2 baris jadi "...") — user minta jangan
                    // kepotong. Bungkus penuh, tinggi kartu menyesuaikan.
                    if (user.about.trim().isNotEmpty)
                      GestureDetector(
                        onTap: onTap,
                        child: Text(
                          user.about.trim(),
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    // Jumlah follower & teman (gaya IG) — di BAWAH About,
                    // hanya bila ada. Ambil dari provider (sumber tunggal)
                    // agar konsisten dgn halaman lain.
                    SocialCountsLine(uid: user.uid),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  Text(
                    statusLabel,
                    style: AppText.caption.copyWith(
                      color: _statusColor(user.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (onUnhide != null)
                        Tooltip(
                          message: s.btnUnhide,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: onUnhide,
                              child: const SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Tombol TAMBAH TEMAN hanya untuk user ter-registrasi.
                      // Lingkaran belakang ikon transparan — ikon saja.
                      if (user.isRegistered)
                        rv.Consumer(
                          builder: (ctx, ref, __) {
                            final (:isFriend, :pending) = ref.watch(
                              socialProvider.select((s) => (
                                isFriend: s.isFriend(user.uid),
                                pending: s.isPendingFriendRequest(user.uid),
                              )),
                            );
                            final sp = ref.read(socialProvider.notifier);
                            final tip = isFriend
                                ? s.btnUnfriend
                                : (pending
                                      ? s.btnCancelRequest
                                      : '${s.btnAddFriend} · ${s.sheetFriendDesc}');
                            return Tooltip(
                              message: tip,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  // Sudah teman → putus teman; terkirim →
                                  // batalkan; belum → kirim permintaan.
                                  onTap: () async {
                                    if (isFriend) {
                                      await runUnfriend(context, sp, user.uid,
                                          user.nickname);
                                    } else if (pending) {
                                      await runCancelRequest(context, sp,
                                          user.uid, user.nickname);
                                    } else {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final res = await sp
                                          .sendFriendRequest(user.uid);
                                      if (!context.mounted) return;
                                      // 'pending' = terkirim; 'friends' = sudah
                                      // teman (bukan error). Selain itu gagal.
                                      if (res == 'pending' ||
                                          res == 'friends') {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              s.friendRequestSentMutual,
                                            ),
                                          ),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          SnackBar(
                                              content: Text(s.errGeneric)),
                                        );
                                      }
                                    }
                                  },
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Icon(
                                      isFriend
                                          ? Icons.group_remove_rounded
                                          : (pending
                                                ? Icons.cancel_rounded
                                                : Icons.person_add_alt_rounded),
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(width: 2),
                      Tooltip(
                        message: s.btnChatNow,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: onTap,
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
