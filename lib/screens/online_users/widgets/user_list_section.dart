import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/regions.dart';
import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../models/user_model.dart';
import '../../../widgets/search_dropdown.dart';
import '../../../widgets/skeleton_card.dart';
import 'online_channel.dart';
import 'filter_dropdown.dart';
import 'hidden_box_widgets.dart';
import 'user_card.dart';

/// Bagian daftar user di halaman Online: filter bar (negara + gender),
/// skeleton/empty state, ListView kartu (dengan swipe-hide), dan kotak
/// "disembunyikan".
///
/// Stateless murni — seluruh state & callback dimiliki oleh layar induk,
/// sehingga perilaku (filter/pagination/scroll) tetap persis sama.
class OnlineUserListSection extends StatelessWidget {
  final S s;
  final OnlineChannel channel;
  final Set<String> friendSet;
  final List<UserModel> users;
  final List<UserModel> hiddenUsers;
  final Map<String, int> unreadMap;
  final bool hasLoaded;
  final bool showHidden;
  final int page;
  final ScrollController scrollCtrl;
  final List<String> negaraSel;
  final String gender;
  final String search;

  final void Function(List<String>) onNegaraChanged;
  final Future<void> Function(String) onGenderChanged;
  final void Function() onToggleHidden;
  final void Function({required bool outOfPoints, required S s}) onOutOfPoints;
  final Future<void> Function(UserModel user) onHideUser;
  final Future<void> Function(UserModel user) onUnhideUser;
  final void Function(BuildContext context, UserModel user) onStartChat;
  final void Function(UserModel user, Color color) onZoomAvatar;
  final void Function(
    BuildContext cardCtx,
    UserModel user,
    int unreadCount,
    Offset pos,
    Rect rect,
  ) onShowUnread;

  const OnlineUserListSection({
    super.key,
    required this.s,
    required this.channel,
    required this.friendSet,
    required this.users,
    required this.hiddenUsers,
    required this.unreadMap,
    required this.hasLoaded,
    required this.showHidden,
    required this.page,
    required this.scrollCtrl,
    required this.negaraSel,
    required this.gender,
    required this.search,
    required this.onNegaraChanged,
    required this.onGenderChanged,
    required this.onToggleHidden,
    required this.onOutOfPoints,
    required this.onHideUser,
    required this.onUnhideUser,
    required this.onStartChat,
    required this.onZoomAvatar,
    required this.onShowUnread,
  });

  @override
  Widget build(BuildContext context) {
    final paged = users.take(page * _pageSize).toList();
    final hasMore = paged.length < users.length;
    // Map uid→index sekali (dulu indexWhere linear per kunci anak
    // → O(n²) saat presence heartbeat menggeser posisi tiap emit).
    final indexByUid = <String, int>{
      for (var i = 0; i < paged.length; i++) paged[i].uid: i,
    };

    return Column(
      children: [
        Padding(
          // Atas 8: label floating butuh ~6px di atas field —
          // kalau 0, label masuk area AppBar dan kepotong.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Row(
            children: [
              Expanded(
                child: FilterDropdown(
                  label: s.labelCountry,
                  icon: Icons.public,
                  items: allCountries,
                  labels: allCountries,
                  selected: negaraSel,
                  countText: s.selCountriesCount,
                  onChanged: onNegaraChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SearchDropdown(
                  value: gender,
                  label: 'Gender',
                  icon: Icons.person_outline,
                  items: const ['all', 'male', 'female'],
                  labels: [s.filterAll, s.filterMale, s.filterFemale],
                  onChanged: onGenderChanged,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: !hasLoaded
              ? ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, _) => const SkeletonCard(),
                )
              : users.isEmpty
              ? _emptyState(context)
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  // Kartu ikut pindah posisi saat urutan berubah
                  // (sort last_seen) — State _AsyncAvatar tidak
                  // di-dispose/recreate → avatar tidak kedip.
                  findChildIndexCallback: (key) {
                    final k = key as ValueKey<String>;
                    // 'uc-<uid>' → index via Map O(1).
                    final uid = k.value.startsWith('uc-')
                        ? k.value.substring(3)
                        : k.value;
                    return indexByUid[uid];
                  },
                  itemCount: paged.length + (hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= paged.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }
                    final user = paged[i];
                    // Geser kiri = Sembunyikan (benam ke kotak bawah).
                    // confirmDismiss=false: kartu tidak terbang,
                    // hanya memicu hide + snackbar Undo.
                    return Dismissible(
                      key: ValueKey('uc-${user.uid}'),
                      direction: DismissDirection.endToStart,
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.textSecondary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.visibility_off_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.btnHide,
                              style: AppText.caption.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      background: const SizedBox.shrink(),
                      // Fire-and-forget: kartu langsung meluncur
                      // balik tanpa menunggu I/O prefs; hide +
                      // snackbar jalan di latar. Kalau di-await,
                      // kartu tertahan terbuka selama future jalan.
                      confirmDismiss: (_) {
                        unawaited(onHideUser(user));
                        return Future.value(false);
                      },
                      // RepaintBoundary: kartu lain tidak ikut
                      // repaint saat satu kartu berubah (badge,
                      // status dot, avatar) — list panjang jadi
                      // jauh lebih murah.
                      child: Builder(
                        builder: (cardCtx) => RepaintBoundary(
                          child: UserCard(
                            user: user,
                            onTap: () => onStartChat(context, user),
                            onAvatarTap: (c) => onZoomAvatar(user, c),
                            onLongPress: unreadMap[user.uid] != null &&
                                    unreadMap[user.uid]! > 0
                                ? (pos, rect) => onShowUnread(
                                      cardCtx,
                                      user,
                                      unreadMap[user.uid]!,
                                      pos,
                                      rect,
                                    )
                                : null,
                            unreadCount: unreadMap[user.uid] ?? 0,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Kotak bawah: yang disembunyikan tetap di bawah walau
        // online, sampai di-release (swipe kanan / tombol).
        // Hanya tampil jika ada isi (hemat ruang).
        if (hiddenUsers.isNotEmpty)
          HiddenBox(
            title: s.labelHidden(hiddenUsers.length),
            expanded: showHidden,
            onToggle: onToggleHidden,
            children: [
              for (final user in hiddenUsers)
                Dismissible(
                  key: ValueKey('hid-${user.uid}'),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.btnUnhide,
                          style: AppText.caption.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  secondaryBackground: const SizedBox.shrink(),
                  confirmDismiss: (_) {
                    unawaited(onUnhideUser(user));
                    return Future.value(false);
                  },
                  child: Builder(
                    builder: (cardCtx) => RepaintBoundary(
                      child: UserCard(
                        user: user,
                        onTap: () => onStartChat(context, user),
                        onAvatarTap: (c) => onZoomAvatar(user, c),
                        onLongPress: unreadMap[user.uid] != null &&
                                unreadMap[user.uid]! > 0
                            ? (pos, rect) => onShowUnread(
                                  cardCtx,
                                  user,
                                  unreadMap[user.uid]!,
                                  pos,
                                  rect,
                                )
                            : null,
                        unreadCount: unreadMap[user.uid] ?? 0,
                        onUnhide: () => onUnhideUser(user),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(
                Icons.group_add_rounded,
                size: 48,
                color: AppTheme.primary,
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            search.isNotEmpty
                ? s.searchNoResult
                : (channel == OnlineChannel.friends
                      ? s.noOnlineFriends
                      : s.noOnlineUsers),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

const int _pageSize = 20;
