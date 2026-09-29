import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';

/// Bottom sheet pemilih orang untuk privasi ("kecuali..." / "hanya orang
/// tertentu").
///
/// Berdiri sendiri sebagai [StatefulWidget] agar ia MEMILIKI
/// [TextEditingController] pencariannya dan membuangnya di [dispose] —
/// waktu yang ditentukan framework saat sheet benar-benar lepas dari pohon.
///
/// Riwayat bug (2026-09-29): dulu controller dibuat di layar pemanggil dan
/// di-`dispose()` tepat setelah `await showModalBottomSheet` selesai. Padahal
/// animasi keluar sheet belum beres — `TextField` masih ter-mount dan
/// memanggil `addListener` pada controller terbuang →
/// `A TextEditingController was used after being disposed` → memicu assertion
/// lanjutan `_dependents.isEmpty` di `InheritedElement`.
///
/// Mengembalikan daftar uid terpilih lewat `Navigator.pop`, atau null bila
/// sheet ditutup tanpa simpan.
class PrivacyExclusionsSheet extends StatefulWidget {
  /// Kandidat: `{'uid','nickname','is_friend'}` (dari PrivacyProvider).
  final List<Map<String, dynamic>> candidates;

  /// Uid yang sudah terpilih sebelumnya.
  final Set<String> initialSelected;

  /// True untuk "hanya orang tertentu" (daftar putih); false = "kecuali".
  final bool isWhitelist;

  final String title;
  final String desc;

  /// String bilingual aktif (dari `LocaleProvider.s` di pemanggil).
  final S s;

  const PrivacyExclusionsSheet({
    super.key,
    required this.candidates,
    required this.initialSelected,
    required this.isWhitelist,
    required this.title,
    required this.desc,
    required this.s,
  });

  @override
  State<PrivacyExclusionsSheet> createState() => _PrivacyExclusionsSheetState();
}

class _PrivacyExclusionsSheetState extends State<PrivacyExclusionsSheet> {
  final TextEditingController _queryCtrl = TextEditingController();
  late final Set<String> _selected = Set<String>.of(widget.initialSelected);
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.candidates;
    final q = _query.toLowerCase();
    return widget.candidates
        .where((e) => '${e['nickname'] ?? ''}'.toLowerCase().contains(q))
        .toList();
  }

  void _save() => Navigator.pop(context, Set<String>.of(_selected));

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final list = widget.candidates;
    final filtered = _filtered;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppText.title),
                        const SizedBox(height: 2),
                        Text(
                          widget.desc,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    child: Text(s.btnSave),
                  ),
                ],
              ),
            ),
            // Kotak pencarian (nama) — mempermudah saat daftar panjang.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _queryCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: s.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _queryCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: AppTheme.divider),
            Expanded(
              child: filtered.isEmpty
                  ? (list.isEmpty
                      ? _EmptyExcludable(s: s)
                      : Center(
                          child: Text(
                            s.searchNoResult,
                            style: AppText.body.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final uid = '${e['uid'] ?? ''}';
                        final name = '${e['nickname'] ?? uid}';
                        final isFriend = e['is_friend'] == true;
                        return CheckboxListTile(
                          value: _selected.contains(uid),
                          activeColor: AppTheme.primary,
                          secondary: _PersonAvatar(name: name),
                          title: Text(name, style: AppText.bodyStrong),
                          subtitle: Text(
                            isFriend
                                ? s.privacyBadgeFriend
                                : s.privacyBadgeAnon,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(uid);
                            } else {
                              _selected.remove(uid);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  final String name;
  const _PersonAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: AppText.label.copyWith(color: AppTheme.primary),
      ),
    );
  }
}

class _EmptyExcludable extends StatelessWidget {
  final S s;
  const _EmptyExcludable({required this.s});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(s.privacyNoFriends, style: AppText.bodyStrong),
            const SizedBox(height: 4),
            Text(
              s.privacyNoFriendsHint,
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
