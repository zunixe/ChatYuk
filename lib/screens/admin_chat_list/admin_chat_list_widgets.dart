import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import '../../config/theme.dart';
import '../../config/strings.dart';
import '../../config/strings_admin.dart';
import '../../core/nav_guard.dart';
import '../../models/active_call_model.dart';
import '../../widgets/app_gesture.dart';
import '../../widgets/gender_avatar.dart';
import '../user_info_screen.dart';
import '../admin_chat_view_screen.dart';
import '../../providers/riverpod/admin_provider.dart';
import '../../providers/riverpod/connectivity_provider.dart';
import '../../utils.dart';

class AdminChatCard extends StatelessWidget {
  final Map<String, dynamic> chat;
  final S s;
  final List<String> adminUids;

  /// Call aktif di chat ini (null = tidak sedang call).
  final ActiveCallInfo? activeCall;

  /// Disematkan admin (ikon pin + border).
  final bool pinned;

  /// Kategori (folder) chat ini (null = tanpa kategori).
  final String? category;

  /// Tahan kartu → buka sheet aksi (pin/kategori).
  final VoidCallback? onLongPressMenu;
  const AdminChatCard({
    required this.chat,
    required this.s,
    required this.adminUids,
    this.activeCall,
    this.pinned = false,
    this.category,
    this.onLongPressMenu,
  });

  /// Buka profil user (sama seperti dari private chat: tap avatar header).
  /// Dipakai avatar peserta di kartu monitor.
  void _openUserProfile(BuildContext context, String uid, String name) {
    if (uid.isEmpty) return;
    final navKey = navKeyUser(uid);
    if (!tryClaimNav(navKey)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: uid, fallbackName: name),
      ),
    ).then((_) => releaseNav(navKey));
  }

  /// Dua avatar peserta (kiri = nama pertama di judul) berdampingan sedikit
  /// tumpang-tindih. Tiap avatar BISA DIKETUK → buka profil user tsb.
  /// Bila tak ada uid (data aneh) → fallback ikon forum seperti dulu.
  ///
  /// [genders] = peta uid→gender (dari `participant_genders`). Untuk peserta
  /// TANPA foto, avatar diberi ring warna gender (male=biru / female=pink /
  /// lain=accent) — sama seperti daftar "Pengguna Online". Foto tetap tanpa
  /// ring (lihat ProfileAvatar: ring hanya muncul di placeholder inisial).
  Widget _avatarPair(
    BuildContext context,
    List<String> uids,
    Map<dynamic, dynamic> names, {
    Map<dynamic, dynamic> genders = const {},
  }) {
    final shown = uids.take(2).toList();
    if (shown.isEmpty) {
      return SizedBox(
        width: 44,
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.forum_outlined,
            color: AppTheme.primary,
            size: 22,
          ),
        ),
      );
    }
    const size = 40.0;
    const overlap = 10.0;
    final width = shown.length == 1 ? size : size * 2 - overlap;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - overlap),
              // Avatar kanan digambar di atas → sisi tumpang terlihat rapi.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openUserProfile(
                  context,
                  shown[i],
                  '${names[shown[i]] ?? ''}',
                ),
                child: Container(
                  // Ring pemisah HANYA saat avatar tumpang-tindih (≥2 peserta)
                  // supaya batas antar-avatar rapi. Avatar TUNGGAL tampil polos
                  // (tanpa border) — persis gaya daftar "Pengguna Online".
                  decoration: shown.length > 1
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bgCard, width: 2),
                        )
                      : null,
                  child: GenderAvatar(
                    uid: shown[i],
                    name: '${names[shown[i]] ?? ''}',
                    gender: '${genders[shown[i]] ?? ''}',
                    size: size,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final genders =
        (chat['participant_genders'] as Map<dynamic, dynamic>?) ?? const {};
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final chatId = '${chat['chat_id'] ?? ''}';
    // Urutan uid DETERMINISTIK dari chatId (uid sorted, abadi) — bukan
    // urutan key `participant_names` (JSONB) yang ikut berubah saat nama
    // di-rename / beda antara snapshot cache & fetch baru. Inilah yang dulu
    // membuat judul "A & B" menukar urutan DAN semua bubble lawan pindah
    // ke kanan saat urutan flip.
    final orderUids = stableChatParticipantOrder(
      chatId: chatId,
      participants: participants.map((p) => '$p').toList(),
    );
    final nameList = [
      for (final u in orderUids)
        if (names[u] != null && '${names[u]}'.isNotEmpty) '${names[u]}',
    ];
    final label = nameList.isNotEmpty
        ? nameList.join(' & ')
        : participants.length == 1
        ? '${participants.length} ${s.adminUserSingular}'
        : '${participants.length} ${s.adminUsersPlural}';
    final lastMsg = (chat['last_message'] as String? ?? '').trim();
    final count = chat['message_count'] ?? 0;
    final tsRaw = chat['last_message_at'];
    final ts = tsRaw != null ? DateTime.tryParse('$tsRaw') : null;

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: activeCall != null
            ? Border.all(color: const Color(0xFF2E9E5B), width: 1.2)
            : pinned
            ? Border.all(color: AppTheme.primary, width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: AppGestureDetector(
        // Tap & long-press via AppGestureDetector (RawGesture, long-press
        // 450ms, tanpa double-tap) — pola sama dgn list chat user & menu
        // Online yang responsif. Dulu `InkWell` di dalam Material: tap
        // menunggu gesture arena Material/ink → terasa lambat saat
        // bulak-balik buka chat monitor.
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPressMenu,
        onTap: () async {
          final id = chat['chat_id'] as String? ?? '';
          // Tap 2× cepat menumpuk 2 route identik → 1× back terlihat mati.
          if (!tryClaimChatPush(id)) return;
          // Panaskan cache pesan MONITOR lalu TUNGGU (pola SAMA dengan chat
          // user: `await prefetchPrivateChat` sebelum push). Dulu ini
          // fire-and-forget → layar mount saat cache belum siap → satu jeda
          // "kosong dulu" lalu terisi (keluhan "harus beberapa kali baru
          // cepet"). Dengan await, `peekChatMessages` PASTI hit saat mount →
          // frame pertama langsung terisi seperti chat user (ala WhatsApp).
          // Baca disk/SQLite-monitor terukur sangat cepat (<10ms) — delay tak
          // terasa, jauh lebih murah daripada menunggu layar render kosong.
          await ProviderScope.containerOf(
            context,
            listen: false,
          ).read(adminProvider).prefetchChatMessages(id);
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminChatViewScreen(
                chatId: id,
                chatLabel: label,
                participantOrder: orderUids,
                participantNames: {
                  for (final e in names.entries) '${e.key}': '${e.value ?? ''}',
                },
                participantGenders: {
                  for (final e in genders.entries)
                    '${e.key}': '${e.value ?? ''}',
                },
              ),
            ),
          ).then((_) => releaseChatPush(id));
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Avatar peserta (menggantikan ikon forum) — tiap avatar
                  // bisa diketuk untuk melihat profil user, sama seperti
                  // dari private chat.
                  _avatarPair(context, orderUids, names, genders: genders),
                  if (activeCall != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: CallActiveBadge(callType: activeCall!.callType),
                    ),
                ],
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pinned || (category != null && category!.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (pinned) ...[
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                s.adminChatPin,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (pinned &&
                                category != null &&
                                category!.isNotEmpty)
                              const SizedBox(width: 8),
                            if (category != null && category!.isNotEmpty) ...[
                              Icon(
                                Icons.folder,
                                size: 12,
                                color: const Color(0xFF7E57C2),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  category!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.micro.copyWith(
                                    color: const Color(0xFF7E57C2),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    SizedBox(height: 3),
                    Text(
                      lastMsg.isEmpty
                          ? (count > 0 ? '$count ${s.adminChatMsgs}' : '')
                          : lastMsg,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (activeCall != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          activeCall!.callType == 'video'
                              ? Icons.videocam
                              : Icons.call,
                          size: 14,
                          color: const Color(0xFF2E9E5B),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          s.adminCallLive,
                          style: AppText.micro.copyWith(
                            color: const Color(0xFF2E9E5B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                  ],
                  if (count > 0)
                    Text(
                      '$count',
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (ts != null) ...[
                    SizedBox(height: 2),
                    Text(
                      formatRelativeTime(ts, isId: s.isId),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showDeleteDialog(context),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final myUids = participants.map((e) => '$e').toList();
    if (myUids.length < 2) return;
    // Aksi tulis: tidak boleh jalan saat offline.
    if (guardOfflineCtx(
      context,
      s.adminNeedsConnection,
      (m) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(m))),
    )) {
      return;
    }

    final selected = <String>{};
    // Secara default centang SEMUA user yang bukan admin.
    for (final uid in myUids) {
      if (!adminUids.contains(uid)) selected.add(uid);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Icon(Icons.delete_forever, color: AppTheme.danger, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.adminDeleteChatTitle,
                    style: AppText.titleEmphasis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.adminDeleteChatBody,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tampilkan SEMUA peserta — sebelumnya hanya 2 pertama yang
                  // muncul di dialog, padahal `selected` berisi semua non-admin
                  // → peserta ke-3+ terhapus diam-diam tanpa persetujuan.
                  for (final uid in myUids)
                    CheckboxListTile(
                      value: selected.contains(uid),
                      onChanged: adminUids.contains(uid)
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? selected.add(uid)
                                  : selected.remove(uid);
                            }),
                      title: Text(
                        '${s.adminDeleteUser}: ${names[uid] ?? 'User'}${adminUids.contains(uid) ? ' ${s.adminCannotDeleteAdmin}' : ''}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      activeColor: AppTheme.danger,
                    ),
                  SizedBox(height: 4),
                  Text(
                    s.adminDeleteChatOnly,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  s.btnCancel,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                child: Text(
                  s.adminDeleteChat,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final admin = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(adminProvider);
    final ok = await admin.deleteChat(
      chat['chat_id'] as String? ?? '',
      selected.toList(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.adminChatDeleted : s.adminDeleteFail)),
    );
    admin.fetchChats();
  }
}

/// Badge call aktif — lingkaran hijau berdenyut dengan icon video/audio.
class CallActiveBadge extends StatefulWidget {
  final String callType;
  const CallActiveBadge({required this.callType});

  @override
  State<CallActiveBadge> createState() => CallActiveBadgeState();
}

class CallActiveBadgeState extends State<CallActiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.55,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF2E9E5B),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.bgCard, width: 2),
        ),
        child: Icon(
          widget.callType == 'video' ? Icons.videocam : Icons.call,
          size: 10,
          color: Colors.white,
        ),
      ),
    );
  }
}
