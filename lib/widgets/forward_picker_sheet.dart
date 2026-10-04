import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/room_provider.dart';
import 'profile_avatar.dart';

class ForwardTarget {
  final String chatType;
  final String chatId;
  final String title;
  final String subtitle;

  /// UID lawan bicara untuk chat private (format `chatId` = `uid1_uid2`,
  /// jadi BUKAN uid user). Dipakai avatar agar cache/foto pakai key yang benar.
  /// Kosong untuk target room.
  final String otherUid;

  /// Gender lawan ('male'/'female'/lainnya) — menentukan warna ring avatar
  /// mengikuti aturan yang sama dengan daftar chat & Pengguna Online.
  final String gender;

  const ForwardTarget({
    required this.chatType,
    required this.chatId,
    required this.title,
    required this.subtitle,
    this.otherUid = '',
    this.gender = '',
  });
}

Future<ForwardTarget?> showForwardSheet(BuildContext context) async {
  return showModalBottomSheet<ForwardTarget>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _ForwardSheet(),
  );
}

class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet();
  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final myUid = auth.uid ?? '';
    final chats = context.read<ChatProvider>().lastPrivateChatsSnapshot(myUid) ?? const [];
    // PERF: `read` (bukan `watch`) — sheet forward dibuka sesaat & langsung
    // dipilih; tidak perlu rebuild tiap RoomProvider notify (provider besar,
    // counts/presence sering). Menghindari storm rebuild saat sheet terbuka.
    final rp = context.read<RoomProvider>();
    final rooms = rp.rooms;
    final groups = rp.myGroups;

    final q = _q.trim().toLowerCase();
    bool match(String v) => q.isEmpty || v.toLowerCase().contains(q);

    final chatTargets = <ForwardTarget>[];
    for (final c in chats) {
      final otherId = c.participants.firstWhere(
        (p) => p != myUid,
        orElse: () => '',
      );
      final name = otherId.isNotEmpty
          ? (c.participantNames[otherId] ?? 'Chat')
          : 'Chat';
      if (!match(name)) continue;
      chatTargets.add(ForwardTarget(
        chatType: 'private',
        chatId: c.chatId,
        title: name,
        subtitle: c.lastMessage,
        otherUid: otherId,
        gender: c.participantGenders[otherId] ?? '',
      ));
    }
    final roomTargets = <ForwardTarget>[];
    for (final r in [...groups, ...rooms]) {
      if (!match(r.name)) continue;
      roomTargets.add(ForwardTarget(
        chatType: 'room',
        chatId: r.id,
        title: '${r.icon} ${r.name}',
        subtitle: '',
      ));
    }
    // Dedup room (groups bisa overlap rooms).
    final seen = <String>{};
    final allRooms = [
      for (final t in roomTargets)
        if (seen.add('${t.chatType}:${t.chatId}')) t,
    ];

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.forwardTitle, style: AppText.bodyStrong),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                style: AppText.body.copyWith(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: s.forwardSearchHint,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              // ListView.builder (lazy): daftar bisa panjang (banyak chat +
              // grup) — dulu `ListView(children:)` membangun SEMUA ListTile
              // sekaligus di satu frame. Entries dibangun ringan (datanya
              // sudah ada), widget-nya dibangun on-demand.
              child: Builder(
                builder: (_) {
                  final entries = <Widget>[];
                  if (chatTargets.isNotEmpty) {
                    entries.add(_sectionHeader(s.titlePrivateChat));
                    for (final t in chatTargets) {
                      entries.add(_chatTile(t));
                    }
                  }
                  if (allRooms.isNotEmpty) {
                    entries.add(_sectionHeader(s.tabPrivateRoom));
                    for (final t in allRooms) {
                      entries.add(_roomTile(t));
                    }
                  }
                  if (chatTargets.isEmpty && allRooms.isEmpty) {
                    entries.add(
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            s.noResults,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) => entries[i],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          text,
          style: AppText.label.copyWith(color: AppTheme.textSecondary),
        ),
      );

  Widget _chatTile(ForwardTarget t) => ListTile(
        dense: true,
        leading: ProfileAvatar(
          // PENTING: uid lawan (bukan chatId) — kalau pakai chatId, key cache
          // & fetch avatar salah → foto tidak pernah muncul. Ring warna
          // mengikuti gender (aturan sama dgn daftar chat & Pengguna Online).
          uid: t.otherUid,
          name: t.title,
          size: 36,
          borderColor: t.gender == 'male'
              ? AppTheme.male
              : t.gender == 'female'
              ? AppTheme.female
              : AppTheme.accent,
          bgColor: AppTheme.avatarBg,
        ),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: t.subtitle.isNotEmpty
            ? Text(
                t.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              )
            : null,
        onTap: () => Navigator.pop(context, t),
      );

  Widget _roomTile(ForwardTarget t) => ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.bgInput,
          child: Text(
            t.title.isNotEmpty ? t.title.characters.first : '?',
            style: TextStyle(fontSize: AppGlyph.sm),
          ),
        ),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.pop(context, t),
      );
}
