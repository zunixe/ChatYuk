import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/room_notifications_provider.dart';
import '../providers/riverpod/room_provider.dart';
import 'profile_style.dart';

/// Buka SIDEBAR notifikasi room/grup (slide dari kanan, ala QuickSideMenu).
///
/// Dipakai HANYA di halaman Chat. Tap baris → tutup sidebar → buka room/grup
/// (lewat [onOpenRoom] milik pemanggil supaya gate password/poin + nav guard
/// tetap dipakai — widget ini tidak menyentuh layar/navigasi langsung).
Future<void> showRoomNotifSidebar(
  BuildContext context, {
  required ValueChanged<RoomModel> onOpenRoom,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Notifikasi',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) =>
        _RoomNotifSidebar(onOpenRoom: onOpenRoom),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _RoomNotifSidebar extends ConsumerStatefulWidget {
  final ValueChanged<RoomModel> onOpenRoom;
  const _RoomNotifSidebar({required this.onOpenRoom});

  @override
  ConsumerState<_RoomNotifSidebar> createState() => _RoomNotifSidebarState();
}

class _RoomNotifSidebarState extends ConsumerState<_RoomNotifSidebar> {
  bool _marking = false;

  /// Cari RoomModel lengkap dari daftar provider (data segar).
  RoomModel? _resolve(String id, bool isGroup) {
    final rp = ref.read(roomProvider);
    for (final g in isGroup ? rp.myGroups : rp.myGlobalRooms) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> _markAllRead(List<RoomNotifItem> items) async {
    if (_marking || items.isEmpty) return;
    setState(() => _marking = true);
    final rp = ref.read(roomProvider.notifier);
    try {
      // Batch 10 paralel (hindari DB storm — pola sama markAllChatsRead).
      for (var i = 0; i < items.length; i += 10) {
        final chunk = items.skip(i).take(10);
        await Future.wait(chunk.map((e) => rp.markRoomRead(e.id)));
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  void _open(RoomNotifItem item) {
    final room = _resolve(item.id, item.isGroup);
    final nav = Navigator.of(context);
    nav.pop();
    if (room != null) widget.onOpenRoom(room);
  }

  String _when(DateTime? t, S s) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}j';
    if (d.inDays < 7) return '${d.inDays}h';
    final l = t.toLocal();
    return '${l.day}/${l.month}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final items = ref.watch(roomNotificationsProvider);
    final width = (MediaQuery.sizeOf(context).width * 0.86).clamp(260.0, 380.0);
    final top = MediaQuery.paddingOf(context).top;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: PColors.bg,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, top + 10, 8, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Notifikasi',
                          style: TextStyle(
                            color: PColors.textStrong,
                            fontSize: AppTextSize.s19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      if (items.isNotEmpty)
                        IconButton(
                          tooltip: s.menuReadAll,
                          onPressed: _marking
                              ? null
                              : () => _markAllRead(items),
                          icon: _marking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.done_all_rounded,
                                  size: 20,
                                  color: PColors.link,
                                ),
                        ),
                      IconButton(
                        tooltip: s.btnClose,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: PColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: PColors.divider),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Tidak ada notifikasi',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: PColors.muted,
                                fontSize: AppTextSize.s135,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            indent: 60,
                            color: PColors.cardDivider,
                          ),
                          itemBuilder: (_, i) {
                            final it = items[i];
                            return InkWell(
                              onTap: () => _open(it),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: PColors.surface,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: _icon(it),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  it.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: PColors.textStrong,
                                                    fontSize: AppTextSize.s145,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _when(it.lastAt, s),
                                                style: const TextStyle(
                                                  color: PColors.faint,
                                                  fontSize: AppTextSize.s115,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  it.preview,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: PColors.muted,
                                                    fontSize: AppTextSize.s13,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 18,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF2F95E8,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                ),
                                                child: Text(
                                                  it.unread > 99
                                                      ? '99+'
                                                      : '${it.unread}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: AppTextSize.s11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(RoomNotifItem it) {
    // Ikon room bisa emoji/teks (disimpan sebagai string) — tampilkan apa
    // adanya; fallback ke ikon grup/room.
    final icon = it.icon.trim();
    if (icon.isNotEmpty && icon.length <= 4) {
      return Text(icon, style: const TextStyle(fontSize: AppTextSize.s17));
    }
    return Icon(
      it.isGroup ? Icons.group_rounded : Icons.public_rounded,
      size: 18,
      color: it.isGroup ? PColors.accent : AppTheme.primary,
    );
  }
}
