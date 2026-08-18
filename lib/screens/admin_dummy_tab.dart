import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/regions.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/admin_service.dart';

/// Tab Dummy di Admin Panel — buat/daftarkan akun dummy (anonymous, tanpa
/// email/password) dengan gender/umur/negara/kota, chat sebagai akun itu
/// (swap sesi tanpa login manual), set status online/idle/offline,
/// dan hapus akun beserta history chat.
class AdminDummyTab extends StatefulWidget {
  const AdminDummyTab({super.key});

  @override
  State<AdminDummyTab> createState() => _AdminDummyTabState();
}

class _AdminDummyTabState extends State<AdminDummyTab> {
  final AdminService _svc = AdminService(SupabaseConfig.client);
  final _nickCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _gender = 'male';
  int _age = 25;
  String _negara = 'Indonesia';
  String _kota = 'Jakarta';
  String? _editingUid;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _svc.listDummies();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[DUMMY] list error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(S s, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _startEdit(Map<String, dynamic> item) {
    _nickCtrl.text = item['nickname'] as String? ?? '';
    _gender = item['gender'] as String? ?? 'male';
    _age = (item['age'] as num?)?.toInt() ?? 25;
    _negara = item['country'] as String? ?? 'Indonesia';
    _kota = item['city'] as String? ?? 'Jakarta';
    setState(() => _editingUid = item['uid'] as String);
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _cancelEdit() {
    _nickCtrl.clear();
    setState(() {
      _editingUid = null;
      _gender = 'male';
      _age = 25;
      _negara = 'Indonesia';
      _kota = 'Jakarta';
    });
  }

  Future<void> _register(S s) async {
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      _toast(s, s.dummyInvalidInput);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_editingUid != null) {
        await _svc.updateDummyProfile(
          uid: _editingUid!,
          nickname: nick,
          gender: _gender,
          age: _age,
          country: _negara,
          city: _kota,
        );
        _toast(s, s.dummyUpdated);
      } else {
        await _svc.registerDummy(
          nickname: nick,
          gender: _gender,
          age: _age,
          country: _negara,
          city: _kota,
        );
        _toast(s, s.dummyRegistered);
      }
      _nickCtrl.clear();
      _editingUid = null;
      await _load();
    } catch (e) {
      debugPrint('[DUMMY] register error: $e');
      _toast(s, _editingUid != null ? s.dummyUpdateFail : s.dummyRegisterFail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status, S s) async {
    try {
      await _svc.setDummyStatus(item['uid'] as String, status);
      await _load();
      _toast(s, s.dummyStatusSet);
    } catch (e) {
      debugPrint('[DUMMY] set status error: $e');
      _toast(s, s.dummySetStatusFail);
    }
  }

  Future<void> _chatAs(Map<String, dynamic> item, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.dummyChatAsTitle),
        content: Text(s.dummyChatAsBody.replaceFirst('%s', item['nickname'] as String? ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.dummyChatAs),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final auth = context.read<AuthProvider>();
    try {
      await auth.becomeDummy(item['uid'] as String);
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _toast(s, s.dummySwapSuccess.replaceFirst('%s', item['nickname'] as String? ?? ''));
    } catch (e) {
      debugPrint('[DUMMY] chat as error: $e');
      _toast(s, s.dummySwapFailed);
    }
  }

  Future<void> _delete(Map<String, dynamic> item, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.dummyDeleteTitle),
        content: Text(s.dummyDeleteBody.replaceFirst('%s', item['nickname'] as String? ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.dummyDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _svc.deleteDummy(item['uid'] as String);
      await _load();
      _toast(s, s.dummyDeleted);
    } catch (e) {
      debugPrint('[DUMMY] delete error: $e');
      _toast(s, s.dummyListFail);
    }
  }

  Color _statusColor(String status) => switch (status) {
        'online' => Color(0xFF2E7D32),
        'idle' => Color(0xFFF9A825),
        _ => AppTheme.textSecondary,
      };

  String _genderLabel(S s, String? gender) =>
      gender == 'female' ? s.labelGenderFemale : s.labelGenderMale;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
        children: [
          // ── Form pendaftaran / edit ──
          Text(_editingUid != null ? s.dummyEdit : s.dummyCreateTitle, style: AppText.titleEmphasis),
          SizedBox(height: 4),
          Text(s.dummyRegisterHint, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          SizedBox(height: 10),
          _SectionCard(
            child: Column(children: [
              TextField(
                controller: _nickCtrl,
                decoration: InputDecoration(
                  labelText: s.dummyNicknameLabel,
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SizedBox(height: 12),

              // Gender
              Row(children: [
                Expanded(child: _genderCard('female', '👩', AppTheme.female, s.labelGenderFemale)),
                SizedBox(width: 12),
                Expanded(child: _genderCard('male', '👨', AppTheme.male, s.labelGenderMale)),
              ]),
              SizedBox(height: 12),

              // Umur & Negara
              Row(children: [
                Expanded(child: _ageDropdown(s)),
                SizedBox(width: 12),
                Expanded(child: _countryDropdown(s)),
              ]),
              SizedBox(height: 12),

              // Kota
              _cityDropdown(s),
              SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _register(s),
                  icon: _busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(
                          _editingUid != null ? Icons.save_outlined : Icons.person_add_alt,
                          size: 18),
                  label: Text(_editingUid != null ? s.dummySaveChanges : s.dummyRegisterBtn),
                ),
              ),
              if (_editingUid != null) ...[
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _cancelEdit,
                    child: Text(s.dummyCancelEdit),
                  ),
                ),
              ],
            ]),
          ),
          SizedBox(height: 20),

          // ── Daftar akun dummy ──
          Row(children: [
            Text(s.dummyListTitle, style: AppText.titleEmphasis),
            Spacer(),
            Text('${_items.length}', style: AppText.label.copyWith(color: AppTheme.textSecondary)),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('${s.dummyListFail}: $_error',
                    style: AppText.bodySmall.copyWith(color: AppTheme.danger)),
              ),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(s.dummyEmpty, style: AppText.bodySmall),
              ),
            )
          else
            ..._items.map((item) => _itemCard(item, s)),
        ],
      ),
    );
  }

  Widget _genderCard(String value, String emoji, Color color, String label) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppTheme.divider, width: selected ? 2 : 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: AppGlyph.sm)),
            SizedBox(width: 6),
            Text(label,
                style: AppText.label.copyWith(
                    color: selected ? color : AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown(S s) {
    return DropdownButtonFormField<int>(
      initialValue: _age,
      decoration: InputDecoration(labelText: s.labelAge),
      isExpanded: true,
      menuMaxHeight: 300,
      items: [for (int i = 13; i <= 80; i++) DropdownMenuItem(value: i, child: Text('$i'))],
      onChanged: (v) {
        if (v != null) setState(() => _age = v);
      },
    );
  }

  Widget _countryDropdown(S s) {
    return DropdownButtonFormField<String>(
      initialValue: _negara,
      decoration: InputDecoration(labelText: s.labelCountry),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [
        for (final n in kotaByNegara.keys)
          DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v == null) return;
        final cities = getCitiesForCountry(v);
        setState(() {
          _negara = v;
          _kota = cities.isNotEmpty ? cities.first : '';
        });
      },
    );
  }

  Widget _cityDropdown(S s) {
    final cities = getCitiesForCountry(_negara);
    if (cities.isEmpty) return const SizedBox.shrink();
    final validKota = cities.contains(_kota) ? _kota : cities.first;
    return DropdownButtonFormField<String>(
      initialValue: validKota,
      decoration: InputDecoration(labelText: s.labelCity),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [for (final k in cities) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
      onChanged: (v) {
        if (v != null) setState(() => _kota = v);
      },
    );
  }

  Widget _itemCard(Map<String, dynamic> item, S s) {
    final nickname = item['nickname'] as String? ?? '';
    final status = item['status'] as String? ?? 'offline';
    final gender = item['gender'] as String? ?? 'male';
    final age = (item['age'] as num?)?.toInt();
    final city = item['city'] as String? ?? '';
    final unread = (item['unread'] as num?)?.toInt() ?? 0;
    final info = [
      _genderLabel(s, gender),
      if (age != null) '$age',
      if (city.isNotEmpty) city,
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: _SectionCard(
        child: Column(children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Text(
                nickname.isEmpty ? '?' : nickname.characters.first.toUpperCase(),
                style: AppText.label.copyWith(color: AppTheme.primary),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong),
                  if (info.isNotEmpty)
                    Text(info,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
            if (unread > 0) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mark_chat_unread, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('$unread', style: AppText.label.copyWith(color: Colors.white)),
                ]),
              ),
              SizedBox(width: 6),
            ],
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                switch (status) {
                  'online' => s.statusOnline,
                  'idle' => s.statusIdle,
                  _ => s.statusOffline,
                },
                style: AppText.label.copyWith(color: _statusColor(status)),
              ),
            ),
          ]),
          SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  _statusChip(item, s.statusOnline, 'online', status, s),
                  _statusChip(item, s.statusIdle, 'idle', status, s),
                  _statusChip(item, s.statusOffline, 'offline', status, s),
                ],
              ),
            ),
            IconButton(
              tooltip: s.dummyEdit,
              onPressed: () => _startEdit(item),
              icon: Icon(Icons.edit_outlined, size: 20, color: AppTheme.textSecondary),
            ),
            IconButton(
              tooltip: s.dummyChatAs,
              onPressed: () => _chatAs(item, s),
              icon: const Icon(Icons.chat_bubble_outline, size: 20, color: AppTheme.primary),
            ),
            IconButton(
              tooltip: s.dummyDelete,
              onPressed: () => _delete(item, s),
              icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _statusChip(Map<String, dynamic> item, String label, String value, String current, S s) {
    final active = current == value;
    return InkWell(
      onTap: () => _setStatus(item, value, s),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _statusColor(value) : _statusColor(value).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: AppText.label.copyWith(
                color: active ? Colors.white : _statusColor(value))),
      ),
    );
  }
}

/// Card putih standar untuk section admin.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }
}
