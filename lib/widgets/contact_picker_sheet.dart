import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/chat_contact.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/device_contacts_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/social_provider.dart';
import 'chat_yuk_chat_header.dart' show ChatFilterChipBar, ChatFilterChipItem;
import 'person_avatar.dart';

/// Pemilih KONTAK untuk dibagikan ke chat (ala WhatsApp) — 2 tab:
///
///  - **ChatYuk**: hanya **teman ∪ yang pernah chat** (sesuai batasan produk).
///    Hasilnya [ChatContact.user] yang payload-nya **hanya uid** (privasi).
///  - **Kontak HP**: buku kontak perangkat (nama + nomor, izin diminta saat tab
///    ini dibuka). Hasilnya [ChatContact.phone].
///
/// Mengembalikan null bila dibatalkan.
Future<ChatContact?> showContactPickerSheet({required BuildContext context}) {
  return showModalBottomSheet<ChatContact>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _ContactPickerSheet(),
  );
}

/// Baris pemilih kontak (ChatYuk).
class ContactPickerUser {
  final String uid;
  final String name;
  final String gender;
  final String avatar;
  const ContactPickerUser({
    required this.uid,
    required this.name,
    required this.gender,
    required this.avatar,
  });
}

/// Gabung **teman ∪ pernah chat** → daftar unik urut nama (fungsi MURNI →
/// mudah diuji tanpa widget/network). [friends] = baris RPC `social_list`,
/// [chatted] = lawan bicara dari daftar Pesan.
List<ContactPickerUser> mergePickerUsers({
  required List<Map<String, dynamic>> friends,
  required List<({String uid, String name, String gender})> chatted,
}) {
  final found = <String, ContactPickerUser>{};
  for (final r in friends) {
    final uid = '${r['uid'] ?? ''}';
    if (uid.isEmpty) continue;
    found[uid] = ContactPickerUser(
      uid: uid,
      name: '${r['nickname'] ?? ''}',
      gender: '${r['gender'] ?? ''}',
      avatar: '${r['avatar'] ?? ''}',
    );
  }
  for (final c in chatted) {
    if (c.uid.isEmpty || found.containsKey(c.uid)) continue;
    found[c.uid] = ContactPickerUser(
      uid: c.uid,
      name: c.name,
      gender: c.gender,
      avatar: '',
    );
  }
  return found.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

class _ContactPickerSheet extends ConsumerStatefulWidget {
  const _ContactPickerSheet();

  @override
  ConsumerState<_ContactPickerSheet> createState() =>
      _ContactPickerSheetState();
}

class _ContactPickerSheetState extends ConsumerState<_ContactPickerSheet> {
  final _searchCtrl = TextEditingController();
  int _tab = 0; // 0 = ChatYuk, 1 = Kontak HP
  String _q = '';

  bool _loadingUsers = true;
  List<ContactPickerUser> _users = const [];

  bool _loadingPhone = false;
  bool _phoneLoaded = false;
  ContactsPermission? _perm;
  List<DeviceContact> _phoneAll = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _q = _searchCtrl.text));
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Teman ∪ pernah-chat (chat yang tampil di tab Pesan), dedupe by uid.
  Future<void> _loadUsers() async {
    final myUid = ref.read(authProvider).uid ?? '';
    if (myUid.isEmpty) {
      if (mounted) setState(() => _loadingUsers = false);
      return;
    }
    var friends = const <Map<String, dynamic>>[];
    var chatted = const <({String uid, String name, String gender})>[];
    // Teman.
    try {
      friends = await ref
          .read(socialProvider.notifier)
          .socialList('friends', myUid, limit: 200);
    } catch (_) {}
    // Pernah chat (snapshot daftar Pesan — stream men-replay snapshot terakhir).
    try {
      final chats = await ref
          .read(chatProvider.notifier)
          .getMyPrivateChats(myUid)
          .first
          .timeout(const Duration(seconds: 3));
      chatted = [
        for (final c in chats)
          if (c.participants.firstWhere(
                (p) => p != myUid,
                orElse: () => '',
              )
              case final other when other.isNotEmpty)
            (
              uid: other,
              name: c.participantNames[other] ?? '',
              gender: c.participantGenders[other] ?? '',
            ),
      ];
    } catch (_) {}
    final list = mergePickerUsers(friends: friends, chatted: chatted);
    if (!mounted) return;
    setState(() {
      _users = list;
      _loadingUsers = false;
    });
  }

  /// Buku kontak HP dimuat LAZY saat tab Kontak HP dibuka (izin baru diminta
  /// saat itu — jangan minta izin kontak hanya karena sheet dibuka).
  Future<void> _loadPhone({bool requestPermission = true}) async {
    if (_loadingPhone) return;
    setState(() => _loadingPhone = true);
    final notifier = ref.read(deviceContactsProvider);
    final perm = await notifier.ensurePermission(request: requestPermission);
    final list = perm == ContactsPermission.granted
        ? await notifier.load(requestPermission: false)
        : const <DeviceContact>[];
    if (!mounted) return;
    setState(() {
      _perm = perm;
      _phoneAll = list;
      _phoneLoaded = true;
      _loadingPhone = false;
    });
  }

  List<ContactPickerUser> get _filteredUsers {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return [
      for (final u in _users)
        if (u.name.toLowerCase().contains(q)) u,
    ];
  }

  List<DeviceContact> get _filteredPhone =>
      DeviceContactsService.filter(_phoneAll, _q);

  Future<void> _pickNumber(DeviceContact c) async {
    final s = ref.read(localeProvider).s;
    var numbers = c.phones;
    if (numbers.length > 1) {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.contactPickNumber),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final n in numbers)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.phone_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    title: Text(n, style: AppText.bodyStrong),
                    onTap: () => Navigator.pop(ctx, n),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.btnCancel),
            ),
          ],
        ),
      );
      if (picked == null) return;
      numbers = [picked];
    }
    if (!mounted) return;
    Navigator.pop(context, ChatContact.phone(c.name, numbers));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle + judul.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.contactPickerTitle,
                      style: AppText.title.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.btnClose,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ChatFilterChipBar(
              items: [
                ChatFilterChipItem(
                  label: s.contactTabChatYuk,
                  active: _tab == 0,
                  onTap: () {
                    if (_tab == 0) return;
                    setState(() => _tab = 0);
                  },
                ),
                ChatFilterChipItem(
                  label: s.contactTabPhone,
                  active: _tab == 1,
                  onTap: () {
                    if (_tab == 1) return;
                    setState(() => _tab = 1);
                    if (!_phoneLoaded) _loadPhone();
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: AppText.body.copyWith(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: s.contactPickerSearch,
                ),
              ),
            ),
            Flexible(
              child: _tab == 0 ? _usersList(s) : _phoneList(s),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab ChatYuk ──
  Widget _usersList(S s) {
    if (_loadingUsers) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final items = _filteredUsers;
    if (items.isEmpty) {
      return _empty(
        s.contactPickerEmpty,
        s.contactPickerEmptyHint,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final u = items[i];
        return ListTile(
          leading: PersonAvatar(
            uid: u.uid,
            name: u.name,
            gender: u.gender,
            avatarB64: u.avatar,
            size: 40,
          ),
          title: Text(
            u.name.isEmpty ? u.uid : u.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong,
          ),
          subtitle: Text(
            s.contactCardLabel,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          onTap: () => Navigator.pop(
            context,
            ChatContact.user(u.uid, name: u.name),
          ),
        );
      },
    );
  }

  // ── Tab Kontak HP ──
  Widget _phoneList(S s) {
    if (_loadingPhone) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final perm = _perm;
    if (perm == ContactsPermission.denied ||
        perm == ContactsPermission.permanentlyDenied) {
      final permanent = perm == ContactsPermission.permanentlyDenied;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts_rounded,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              s.contactPermissionTitle,
              style: AppText.bodyStrong,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              permanent ? s.contactPermissionDenied : s.contactPermissionBody,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => permanent
                  ? ref.read(deviceContactsProvider).openSettings()
                  : _loadPhone(),
              child: Text(permanent ? s.btnOpenSettings : s.btnAllow),
            ),
          ],
        ),
      );
    }
    final items = _filteredPhone;
    if (items.isEmpty) {
      return _empty(s.contactPhoneEmpty, s.contactPickerEmptyHint);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final initial = c.name.isNotEmpty ? c.name.characters.first : '?';
        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.bgInput,
            child: Text(
              initial.toUpperCase(),
              style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
            ),
          ),
          title: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong,
          ),
          subtitle: Text(
            c.phones.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          onTap: () => _pickNumber(c),
        );
      },
    );
  }

  Widget _empty(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.contact_page_outlined,
            size: 40,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 10),
          Text(title, style: AppText.bodyStrong, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            hint,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
