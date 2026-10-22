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
import 'group/create_group_sheet.dart';
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
            // RepaintBoundary per kartu: kartu membawa shadow blur 8 +
            // Dismissible; tanpa layer sendiri, perubahan satu kartu menandai
            // seluruh list untuk repaint (pola sama list Online/Chat).
            itemBuilder: (_, i) => RepaintBoundary(
              child: GroupCard(room: rooms[i]),
            ),
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
  if (!context.mounted) return;

  int paidCostOf(bool withPw) =>
      withPw ? points.roomCreatePwPaid : points.roomCreatePaid;
  var outOfPoints = false;
  var createdName = '';

  // Sheet Buat Grup (desain 2026-10-18) — validasi, error inline & biaya
  // koin ada di sheet; logika bisnis (RPC, gate, pemetaan error) di sini.
  final res = await showCreateGroupSheet<Map<String, dynamic>>(
    context,
    s: s,
    // Biaya + saldo — sembunyi saat sistem poin OFF / build admin.
    costLabel: (points.enabled && !isAdmin)
        ? (withPw) {
            final paid = paidCostOf(withPw);
            return '${s.paidOrBonus(paid, paid * points.bonusMultiplier)}'
                '  ·  ${points.points}';
          }
        : null,
    onCreate: (draft) async {
      final paid = paidCostOf(draft.withPassword);
      if (points.enabled &&
          !isAdmin &&
          points.points < paid &&
          points.points < paid * points.bonusMultiplier) {
        outOfPoints = true;
        return null; // tutup sheet → dialog koin kurang
      }
      createdName = draft.name;
      try {
        return await ProviderScope.containerOf(context, listen: false)
            .read(roomProvider.notifier)
            .createPrivateRoom(
              name: draft.name,
              icon: draft.iconEmoji,
              password: draft.password,
            );
      } catch (e) {
        final msg = e.toString();
        throw CreateGroupFailure(
          msg.contains('Room limit')
              ? s.errGroupLimit
              : msg.contains('REGISTERED_ONLY')
              ? s.msgVerifyToUsePaid
              : msg.contains('Not enough')
              ? s.errCoinInsufficient
              : msg.contains('Invalid room name')
              ? s.errRoomNameLen
              : s.errCreateGroupRetry,
        );
      }
    },
  );
  if (!context.mounted) return;
  if (outOfPoints) {
    points.showOutOfPointsDialog(context, s.isId);
    return;
  }
  if (res == null) return; // dibatalkan
  if (res['points'] != null) {
    points.setPoints((res['points'] as num).toInt());
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(s.groupCreated)),
  );
  // List milikku berubah (grup baru) — muat ulang.
  _GroupListState.reloadCurrent(context);
  // Langkah 2: tawarkan UNDANG anggota (atau lewati) sebelum masuk grup.
  final newId = '${res['id'] ?? ''}';
  if (newId.isNotEmpty) {
    await showGroupInviteStep(
      context,
      roomId: newId,
      roomName: createdName,
    );
  }
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
