import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/admin_gate.dart';
import '../core/perf/perf_probe.dart';
import '../models/room_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/empty_state_view.dart';
import 'group/group_widgets.dart';
import 'room_members_sheet.dart';
import '../widgets/person_avatar.dart';
import '../config/theme.dart';

/// Tab "Grup": list grup private milikku + FAB buat grup.
/// Dipindah dari lobby_screen (dulu tab Private di dalam Room).
/// [externalQuery]: filter nama dari ikon cari AppBar (pola Pesan).
class GroupScreen extends StatefulWidget {
  final String? externalQuery;
  const GroupScreen({super.key, this.externalQuery});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  /// Akses statis untuk memuat-ulang list dari dialog buat grup.
  static final GlobalKey<_GroupListState> _listKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return _GroupList(key: _listKey, externalQuery: widget.externalQuery);
  }
}

class _GroupList extends ConsumerStatefulWidget {
  final String? externalQuery;
  const _GroupList({super.key, this.externalQuery});
  @override
  ConsumerState<_GroupList> createState() => _GroupListState();
}

class _GroupListState extends ConsumerState<_GroupList> {
  /// Muat-ulang dari luar (dialog buat grup) — langsung ke provider supaya
  /// jalan dari konteks mana pun (FAB tab Grup maupun menu ⋮ chat list yang
  /// tidak punya _GroupListState sebagai ancestor).
  static void reloadCurrent(BuildContext context) {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier).loadMyGroups(refresh: true);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// List grup MILIKKU dari RoomProvider (cache memori/TTL/disk — klik tab
  /// instan, spinner hanya saat cache benar-benar kosong). Grup expired
  /// disembunyikan kecuali milik sendiri (owner bisa perpanjang).
  Future<void> _load({bool refresh = false}) async {
    await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(roomProvider.notifier).loadMyGroups(refresh: refresh);
  }

  List<RoomModel> _visibleGroups(List<RoomModel> myGroups) {
    final myUid =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(roomProvider.notifier).prvUid ??
        '';
    final now = DateTime.now();
    return myGroups.where((m) {
      final expired = m.expiresAt != null && m.expiresAt!.isBefore(now);
      return !(expired && m.ownerId != myUid);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Group');
    final s = ref.watch(localeProvider).s;
    // PERF: dulu `watch<RoomProvider>()` penuh → SELURUH daftar grup rebuild
    // tiap RoomProvider notify (4 realtime sub: counts/private/membership/
    // presence → sering). `select` hanya field yang dirender; `myGroups`
    // adalah field tersimpan (identity stabil) → rebuild hanya saat benar
    // berubah.
    final myGroups = ref.watch(roomProvider.select((rp) => rp.myGroups));
    final myGroupsLoading = ref.watch(
      roomProvider.select((rp) => rp.myGroupsLoading),
    );
    final q = (widget.externalQuery ?? '').trim().toLowerCase();
    final rooms = q.isEmpty
        ? _visibleGroups(myGroups)
        : _visibleGroups(
            myGroups,
          ).where((r) => r.name.toLowerCase().contains(q)).toList();
    final searching = q.isNotEmpty;
    if (myGroupsLoading && rooms.isEmpty && !searching) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppTheme.primary,
          ),
        ),
      );
    }
    return Stack(
      children: [
        if (rooms.isEmpty)
          EmptyStateView(
            icon: searching ? Icons.search_off_rounded : Icons.lock_rounded,
            title: searching ? s.searchNoResult : s.noGroups,
            hint: searching ? '' : s.noGroupsHint,
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 88),
            itemCount: rooms.length,
            itemBuilder: (_, i) => GroupCard(room: rooms[i]),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => showCreateGroupDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark,
                      AppTheme.primary,
                      AppTheme.accent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.btnCreateGroup,
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _roomIconChoices = [
  '🔒',
  '💬',
  '🎉',
  '🎮',
  '🎵',
  '💘',
  '🔥',
  '⭐',
  '🌙',
  '👑',
  '☕',
  '🌸',
];

/// Dialog buat grup — publik: dipakai FAB tab Grup DAN menu ⋮ chat list.
Future<void> showCreateGroupDialog(BuildContext context) async {
  final s = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localeProvider).s;
  final points = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(pointsProvider.notifier);
  final auth = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(authProvider.notifier);
  // Admin privilege hanya ada di build admin (flavor-gate) —
  // bukan lagi cek email runtime.
  final isAdmin = AdminGate.enabled;
  // Gate ANON: bikin grup khusus terdaftar (server juga menolak).
  // Sesi dummy (admin jadi anon) diizinkan — server bypass dummy.
  if (auth.isAnonymous && !auth.dummySessionActive) {
    final ls = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    showAnonPromptDialog(
      context,
      title: ls.promptCompleteEmailGroupTitle,
      message: ls.promptCompleteEmailGroupMsg,
      icon: Icons.groups_outlined,
    );
    return;
  }
  final nameCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  String icon = '🔒';

  await points.refreshRoomPricing();

  // Room private (berbayar) butuh email terverifikasi. Anon tetap bisa
  // memakai tier bonus (beli lewat koin bonus), tapi tetap harus registered
  // + verified untuk fitur berbayar penuh.
  if (!isAdmin && points.enabled && !auth.canUsePaid && !auth.isAnonymous) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
    }
    return;
  }

  bool usePw = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final paidCost = usePw
            ? points.roomCreatePwPaid
            : points.roomCreatePaid;
        final bonusCost = paidCost * points.bonusMultiplier;
        return Dialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryDark,
                            AppTheme.primary,
                            AppTheme.accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.group_add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.createGroupTitle, style: AppText.title),
                          const SizedBox(height: 2),
                          Text(
                            s.createGroupSubtitle,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(s.groupNameLabel, style: AppText.label),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  maxLength: 30,
                  style: AppText.body.copyWith(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: s.groupNameHint,
                    prefixIcon: const Icon(Icons.edit_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 14),
                Text(s.roomIconLabel, style: AppText.label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _roomIconChoices
                      .map(
                        (e) => GestureDetector(
                          onTap: () => setInner(() => icon = e),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: icon == e
                                  ? AppTheme.primary.withValues(alpha: 0.15)
                                  : AppTheme.bgScreen,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: icon == e
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary.withValues(
                                        alpha: 0.25,
                                      ),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                e,
                                style: TextStyle(fontSize: AppGlyph.sm),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),
                Text(s.groupAccessLabel, style: AppText.label),
                const SizedBox(height: 6),
                GroupAccessCard(
                  selected: !usePw,
                  icon: Icons.all_inclusive_rounded,
                  color: AppTheme.online,
                  title: s.groupNoPwTitle,
                  desc: s.groupNoPwDesc,
                  onTap: () => setInner(() => usePw = false),
                ),
                const SizedBox(height: 8),
                GroupAccessCard(
                  selected: usePw,
                  icon: Icons.lock_rounded,
                  color: AppTheme.primary,
                  title: s.groupPwTitle,
                  desc: s.groupPwDesc,
                  onTap: () => setInner(() => usePw = true),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: usePw
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: pwCtrl,
                            obscureText: true,
                            onChanged: (_) => setInner(() {}),
                            style: AppText.body.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: s.roomPasswordHint,
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Biaya + saldo koin — sembunyikan saat sistem poin OFF (room gratis diam-diam)
                if (points.enabled && !isAdmin) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '🪙',
                          style: TextStyle(fontSize: AppGlyph.sm),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.paidOrBonus(paidCost, bonusCost),
                            style: AppText.bodyStrong.copyWith(
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        Text(
                          '${points.points}',
                          style: AppText.bodyStrong.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final name = nameCtrl.text.trim();
                      if (name.length < 3 || name.length > 30) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(s.errRoomNameLen)),
                        );
                        return;
                      }
                      if (usePw && pwCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(s.errPasswordRequired)),
                        );
                        return;
                      }
                      if (points.enabled &&
                          !isAdmin &&
                          points.points < paidCost &&
                          points.points < bonusCost) {
                        Navigator.pop(ctx);
                        points.showOutOfPointsDialog(context, s.isId);
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final res =
                            await ProviderScope.containerOf(
                                  context,
                                  listen: false,
                                )
                                .read(roomProvider.notifier)
                                .createPrivateRoom(
                                  name: name,
                                  icon: icon,
                                  password: usePw ? pwCtrl.text.trim() : null,
                                );
                        if (res['points'] != null) {
                          points.setPoints((res['points'] as num).toInt());
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          SnackBar(content: Text(s.groupCreated)),
                        );
                        if (context.mounted) {
                          // List milikku berubah (grup baru) — muat ulang.
                          _GroupListState.reloadCurrent(context);
                          // Langkah 2: tawarkan UNDANG anggota (atau lewati)
                          // sebelum masuk grup. Tidak memblokir (bisa ditutup).
                          final newId = '${res['id'] ?? ''}';
                          if (newId.isNotEmpty) {
                            await showGroupInviteStep(
                              context,
                              roomId: newId,
                              roomName: name,
                            );
                          }
                        }
                      } catch (e) {
                        final msg = e.toString();
                        final show = msg.contains('Room limit')
                            ? s.errGroupLimit
                            : msg.contains('REGISTERED_ONLY')
                            ? s.msgVerifyToUsePaid
                            : msg.contains('Not enough')
                            ? s.errCoinInsufficient
                            : msg.contains('Invalid room name')
                            ? s.errRoomNameLen
                            : s.errSendCoin;
                        messenger.showSnackBar(SnackBar(content: Text(show)));
                      }
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryDark,
                            AppTheme.primary,
                            AppTheme.accent,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.btnCreateGroup,
                        style: AppText.button.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.btnCancel),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Langkah 2 setelah buat grup: tawarkan UNDANG anggota (opsional) atau
/// selesai. Owner bisa undang beberapa (picker tetap terbuka), lihat chip
/// "Terundang (n)", lalu tutup. Bila tak ada yang diundang = lewati.
Future<void> showGroupInviteStep(
  BuildContext context, {
  required String roomId,
  required String roomName,
}) async {
  final s = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localeProvider).s;
  final invited = <String, (String, String)>{}; // uid → (nama, gender)
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) => Dialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryDark,
                          AppTheme.primary,
                          AppTheme.accent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.group_add_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.privateRoomsInviteMembers, style: AppText.title),
                        const SizedBox(height: 2),
                        Text(
                          roomName,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.roomInviteHint,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(s.privateRoomsInviteMembers),
                onPressed: () async {
                  await showGroupInvitePicker(
                    context: ctx,
                    roomId: roomId,
                    excludeUids: invited.keys.toSet(),
                    onInvited: () {},
                    onInvitedOne: (uid, name, gender) {
                      if (ctx.mounted) {
                        setInner(() => invited[uid] = (name, gender));
                      }
                    },
                  );
                },
              ),
              if (invited.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  s.privateRoomsInvitedCount(invited.length),
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final e in invited.entries)
                      Chip(
                        avatar: PersonAvatar(
                          uid: e.key,
                          name: e.value.$1,
                          gender: e.value.$2,
                          size: 22,
                        ),
                        label: Text(e.value.$1, style: AppText.micro),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(invited.isEmpty ? s.btnSkip : s.btnDone),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
