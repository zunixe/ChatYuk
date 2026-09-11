import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/regions.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../core/admin_gate.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/admin_service.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap "masuk dummy")
/// — kalau tidak, semua RPC admin melempar 'Unauthorized' (P0001).
/// Cek di client supaya pesannya jelas; server tetap sumber kebenaran.
bool _isAdminSession() =>
    AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

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
      dlog('[DUMMY] list error: $e');
      if (!mounted) return;
      final s = context.read<LocaleProvider>().s;
      setState(() {
        _error =
            '$e'.contains('Unauthorized') ? s.dummyNeedAdmin : e.toString();
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
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
    // Validasi sama dengan sheet Edit Profil (3-20, format) — RPC server
    // juga menolak nickname di luar range ini (dummy_profile_edit_fix).
    if (nick.length < 3) {
      _toast(s, s.errNicknameShort);
      return;
    }
    if (nick.length > 20) {
      _toast(s, s.errNicknameLong);
      return;
    }
    if (!isValidNickname(nick)) {
      _toast(s, s.errNicknameInvalid);
      return;
    }
    if (!_isAdminSession()) {
      _toast(s, s.dummyNeedAdmin);
      return;
    }
    setState(() => _busy = true);
    try {
      // Pre-check duplikat — error spesifik sebelum kirim ke server
      // (server tetap validasi sebagai sumber kebenaran, case-insensitive).
      final available = await _svc.isNicknameAvailable(
        nick,
        excludeUid: _editingUid,
      );
      if (!available) {
        if (!mounted) return;
        setState(() => _busy = false);
        _toast(s, s.errNicknameTaken);
        return;
      }
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
    } catch (e, st) {
      // print (bukan dlog) — muncul di logcat release untuk diagnosis.
      // ignore: avoid_print
      print('[DUMMY] save error: $e');
      // ignore: avoid_print
      print('[DUMMY] stack: ${st.toString().split('\n').take(6).join('\n')}');
      final msg = '$e'.replaceFirst('Exception: ', '');
      _toast(
        s,
        '${_editingUid != null ? s.dummyUpdateFail : s.dummyRegisterFail}: $msg',
      );
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
      dlog('[DUMMY] set status error: $e');
      _toast(s, s.dummySetStatusFail);
    }
  }

  Future<void> _chatAs(Map<String, dynamic> item, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.dummyChatAsTitle),
        content: Text(
          s.dummyChatAsBody.replaceFirst(
            '%s',
            item['nickname'] as String? ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
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
      _toast(
        s,
        s.dummySwapSuccess.replaceFirst(
          '%s',
          item['nickname'] as String? ?? '',
        ),
      );
    } catch (e) {
      dlog('[DUMMY] chat as error: $e');
      _toast(s, s.dummySwapFailed);
    }
  }

  Future<void> _delete(Map<String, dynamic> item, S s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.dummyDeleteTitle),
        content: Text(
          s.dummyDeleteBody.replaceFirst(
            '%s',
            item['nickname'] as String? ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
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
      dlog('[DUMMY] delete error: $e');
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
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          // ── Form pendaftaran / edit ──
          Text(
            _editingUid != null ? s.dummyEdit : s.dummyCreateTitle,
            style: AppText.titleEmphasis,
          ),
          SizedBox(height: 4),
          Text(
            s.dummyRegisterHint,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          SizedBox(height: 10),
          _SectionCard(
            child: Column(
              children: [
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
                Row(
                  children: [
                    Expanded(
                      child: _genderCard(
                        'female',
                        '👩',
                        AppTheme.female,
                        s.labelGenderFemale,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _genderCard(
                        'male',
                        '👨',
                        AppTheme.male,
                        s.labelGenderMale,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),

                // Umur & Negara
                Row(
                  children: [
                    Expanded(child: _ageDropdown(s)),
                    SizedBox(width: 12),
                    Expanded(child: _countryDropdown(s)),
                  ],
                ),
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _editingUid != null
                                ? Icons.save_outlined
                                : Icons.person_add_alt,
                            size: 18,
                          ),
                    label: Text(
                      _editingUid != null
                          ? s.dummySaveChanges
                          : s.dummyRegisterBtn,
                    ),
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
              ],
            ),
          ),
          SizedBox(height: 20),

          // ── Daftar akun dummy ──
          Row(
            children: [
              Text(s.dummyListTitle, style: AppText.titleEmphasis),
              Spacer(),
              Text(
                '${_items.length}',
                style: AppText.label.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
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
                child: Text(
                  '${s.dummyListFail}: $_error',
                  style: AppText.bodySmall.copyWith(color: AppTheme.danger),
                ),
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
          border: Border.all(
            color: selected ? color : AppTheme.divider,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: AppGlyph.sm)),
            SizedBox(width: 6),
            Text(
              label,
              style: AppText.label.copyWith(
                color: selected ? color : AppTheme.textSecondary,
              ),
            ),
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
      items: [
        for (int i = 18; i <= 80; i++)
          DropdownMenuItem(value: i, child: Text('$i')),
      ],
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
          DropdownMenuItem(
            value: n,
            child: Text(n, overflow: TextOverflow.ellipsis),
          ),
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
      items: [
        for (final k in cities)
          DropdownMenuItem(
            value: k,
            child: Text(k, overflow: TextOverflow.ellipsis),
          ),
      ],
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
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    nickname.isEmpty
                        ? '?'
                        : nickname.characters.first.toUpperCase(),
                    style: AppText.label.copyWith(color: AppTheme.primary),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                      if (info.isNotEmpty)
                        Text(
                          info,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mark_chat_unread,
                          size: 12,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '$unread',
                          style: AppText.label.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 8),
            // Baris aksi rapi: chip status + AI nempel sejajar (wrap),
            // tombol ikon kanan berukuran seragam 40x44.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _statusChip(item, s.statusOnline, 'online', status, s),
                      _statusChip(item, s.statusIdle, 'idle', status, s),
                      _statusChip(item, s.statusOffline, 'offline', status, s),
                      _aiChip(item, s),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: s.dummyEdit,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _startEdit(item),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
                IconButton(
                  tooltip: s.dummyChatAs,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _chatAs(item, s),
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ),
                IconButton(
                  tooltip: s.dummyDelete,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(item, s),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Chip AI dummy: aktif = terang + ikon robot; tap = buka sheet persona.
  Widget _aiChip(Map<String, dynamic> item, S s) {
    final aiOn = item['ai_enabled'] == true;
    return InkWell(
      onTap: () => _openAiSheet(item, s),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: aiOn ? AppTheme.accent : AppTheme.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 13,
              color: aiOn ? Colors.white : AppTheme.accent,
            ),
            const SizedBox(width: 4),
            Text(
              s.dummyAiChip,
              style: AppText.label.copyWith(
                color: aiOn ? Colors.white : AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAiSheet(Map<String, dynamic> item, S s) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DummyAiSheet(item: item),
    );
    if (saved == true) await _load();
  }

  Widget _statusChip(
    Map<String, dynamic> item,
    String label,
    String value,
    String current,
    S s,
  ) {
    final active = current == value;
    return InkWell(
      onTap: () => _setStatus(item, value, s),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? _statusColor(value)
              : _statusColor(value).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: active ? Colors.white : _statusColor(value),
          ),
        ),
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

/// Sheet Mode AI dummy: switch aktif + persona opsional (kepribadian,
/// gaya bicara, prompt tambahan). Nama/umur/kota/hobi otomatis dari
/// profil dummy — tidak diisi manual.
class _DummyAiSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  const _DummyAiSheet({required this.item});

  @override
  State<_DummyAiSheet> createState() => _DummyAiSheetState();
}

class _DummyAiSheetState extends State<_DummyAiSheet> {
  /// Parse jam aktif dari RPC (List num) — aman untuk format basi.
  static List<int> _parseHours(dynamic v) {
    if (v is! List) return const [];
    final out = <int>[];
    for (final e in v) {
      final n = e is num ? e.toInt() : int.tryParse('$e');
      if (n != null && n >= 0 && n <= 23 && !out.contains(n)) out.add(n);
    }
    out.sort();
    return out;
  }

  /// Ringkasan jam aktif: "08–23" bila kontinu, "08,12,20–22" bila tidak.
  static String _hoursSummary(List<int> hours) {
    if (hours.isEmpty) return '';
    final parts = <String>[];
    var start = hours.first;
    var prev = start;
    String fmt(int h) => h.toString().padLeft(2, '0');
    for (var i = 1; i <= hours.length; i++) {
      final cur = i < hours.length ? hours[i] : -99;
      if (cur == prev + 1) {
        prev = cur;
        continue;
      }
      parts.add(start == prev ? fmt(start) : '${fmt(start)}–${fmt(prev)}');
      start = cur;
      prev = cur;
    }
    return parts.join(', ');
  }
  late bool _enabled;
  int _guardSel = 0; // 0 = ikuti global, 1 = ON, 2 = OFF
  late bool _schedAuto;
  late List<int> _hours;
  bool _schedBusy = false;
  late final TextEditingController _personalityCtrl;
  late final TextEditingController _toneCtrl;
  late final TextEditingController _extraCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final persona =
        (widget.item['ai_persona'] as Map<dynamic, dynamic>?) ?? const {};
    _enabled = widget.item['ai_enabled'] == true;
    final g = widget.item['ai_guard_enabled'];
    _guardSel = g == true ? 1 : g == false ? 2 : 0;
    _schedAuto = (widget.item['ai_schedule_auto'] as bool?) ?? true;
    _hours = _parseHours(widget.item['ai_active_hours']);
    _personalityCtrl = TextEditingController(text: '${persona['personality'] ?? ''}');
    _toneCtrl = TextEditingController(text: '${persona['tone'] ?? ''}');
    _extraCtrl = TextEditingController(text: '${persona['extra_prompt'] ?? ''}');
  }

  @override
  void dispose() {
    _personalityCtrl.dispose();
    _toneCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<LocaleProvider>().s;
    if (!_isAdminSession()) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.dummyNeedAdmin)));
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = AdminService(SupabaseConfig.client);
      final guardValue = _guardSel == 0 ? null : _guardSel == 1;
      await svc.setDummyAi(
        widget.item['uid'] as String,
        _enabled,
        {
          if (_personalityCtrl.text.trim().isNotEmpty)
            'personality': _personalityCtrl.text.trim(),
          if (_toneCtrl.text.trim().isNotEmpty) 'tone': _toneCtrl.text.trim(),
          if (_extraCtrl.text.trim().isNotEmpty)
            'extra_prompt': _extraCtrl.text.trim(),
        },
        guardEnabled: guardValue,
      );
      widget.item['ai_guard_enabled'] = guardValue;
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.dummyAiSaved)));
    } catch (e) {
      dlog('[DUMMY] save AI error: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = '$e'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${s.dummyAiSaveFail}: $msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final nickname = widget.item['nickname'] as String? ?? '';
    // + padding.bottom = navbar Android (gesture/3-button) supaya tombol
    // Simpan tidak tertutup menu sistem.
    final bottom = MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${s.dummyAiTitle} — $nickname',
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              s.dummyAiDesc,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: Text(s.dummyAiEnabledLabel, style: AppText.bodyStrong),
              activeThumbColor: AppTheme.primary,
            ),
            const SizedBox(height: 6),
            Text(s.aiGlobalGuardTitle, style: AppText.bodyStrong),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Global')),
                ButtonSegment(value: 1, label: Text('ON')),
                ButtonSegment(value: 2, label: Text('OFF')),
              ],
              selected: {_guardSel},
              onSelectionChanged: (v) => setState(() => _guardSel = v.first),
            ),
            const SizedBox(height: 2),
            Text(
              s.dummyAiGuardHint,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            // ── Jadwal kehadiran AI ──
            // Cronjob online/idle/offline mengikuti jam aktif; offline =
            // AI tidak membalas sama sekali. Jadwal dari kebiasaan chat.
            Text(s.dummyAiScheduleTitle, style: AppText.bodyStrong),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _schedAuto,
              onChanged: (v) => setState(() => _schedAuto = v),
              title: Text(
                s.dummyAiScheduleAutoLabel,
                style: AppText.bodySmall,
              ),
              activeThumbColor: AppTheme.primary,
            ),
            Text(
              s.dummyAiScheduleAutoDesc,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hours.isEmpty
                  ? s.dummyAiScheduleEmpty
                  : '${_hoursSummary(_hours)} WIB',
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              s.dummyAiScheduleDesc,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _schedBusy
                  ? null
                  : () async {
                      if (!_isAdminSession()) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(content: Text(s.dummyNeedAdmin)),
                          );
                        return;
                      }
                      setState(() => _schedBusy = true);
                      try {
                        final svc =
                            AdminService(SupabaseConfig.client);
                        final hours = await svc.autoScheduleAi(
                          widget.item['uid'] as String,
                        );
                        if (!mounted) return;
                        setState(() {
                          _schedBusy = false;
                          _hours = hours;
                        });
                        // Sinkron ke map item (shared reference dgn list
                        // induk) supaya buka-ulang sheet langsung tampil
                        // jadwal baru tanpa reload + spinner.
                        widget.item['ai_active_hours'] = hours;
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                hours.isEmpty
                                    ? s.dummyAiSaveFail
                                    : '${s.dummyAiSaved} (${_hoursSummary(hours)} WIB)',
                              ),
                            ),
                          );
                      } catch (e) {
                        dlog('[DUMMY] autoschedule error: $e');
                        if (!mounted) return;
                        setState(() => _schedBusy = false);
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(s.dummyAiSaveFail),
                            ),
                          );
                      }
                    },
              icon: _schedBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.schedule_rounded, size: 18),
              label: Text(s.dummyAiScheduleAuto),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _personalityCtrl,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: s.dummyAiPersonality,
                hintText: s.dummyAiPersonalityAuto,
                hintStyle: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toneCtrl,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: s.dummyAiTone,
                hintText: s.dummyAiToneAuto,
                hintStyle: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _extraCtrl,
              style: AppText.body,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: s.dummyAiExtra,
                hintText: s.dummyAiExtraHint,
                hintStyle: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(s.btnSave),
            ),
          ],
        ),
      ),
    );
  }
}
