import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/regions.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../core/admin_gate.dart';
import '../providers/auth_provider.dart';
import '../widgets/profile_form_card.dart';
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
  final _nicknameFocus = FocusNode();
  String? _nicknameError;
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  String _search = '';
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
    _nicknameFocus.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
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

  /// Daftar dummy terfilter pencarian (by nickname, case-insensitive).
  /// Query kosong = semua item.
  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _items;
    final q = _search.toLowerCase();
    return _items
        .where(
          (m) => (m['nickname'] as String? ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  void _toast(S s, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Isi form dari item untuk mode edit. Tanpa setState/scroll —
  /// dipanggil tepat sebelum bottom sheet dibuka (sheet membaca nilai
  /// fresh saat build).
  void _fillForm(Map<String, dynamic> item) {
    _nickCtrl.text = item['nickname'] as String? ?? '';
    _nicknameError = null;
    _gender = item['gender'] as String? ?? 'male';
    _age = (item['age'] as num?)?.toInt() ?? 25;
    _negara = item['country'] as String? ?? 'Indonesia';
    _kota = item['city'] as String? ?? 'Jakarta';
    _busy = false;
    _editingUid = item['uid'] as String;
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

  void _onNicknameChanged(String v, StateSetter setSheet) {
    // Validasi live — sama seperti register screen.
    final nick = v.trim();
    String? err;
    if (nick.isNotEmpty) {
      final s = context.read<LocaleProvider>().s;
      if (nick.length < 3) {
        err = s.errNicknameShort;
      } else if (nick.length > 20) {
        err = s.errNicknameLong;
      } else if (!isValidNickname(nick)) {
        err = s.errNicknameInvalid;
      }
    }
    setSheet(() => _nicknameError = err);
  }

  /// Simpan form dummy (dipakai dari bottom sheet — setSheet me-rebuild
  /// isi sheet, bukan tab). sheetCtx = context sheet untuk pop.
  /// _formSheetOpen guard: user bisa swipe-dismiss sheet di tengah RPC.
  Future<void> _register(
    S s,
    StateSetter setSheet,
    BuildContext sheetCtx,
  ) async {
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
    if (_formSheetOpen) setSheet(() => _busy = true);
    try {
      // Pre-check duplikat — error spesifik sebelum kirim ke server
      // (server tetap validasi sebagai sumber kebenaran, case-insensitive).
      final available = await _svc.isNicknameAvailable(
        nick,
        excludeUid: _editingUid,
      );
      if (!available) {
        if (!mounted) return;
        if (_formSheetOpen) setSheet(() => _busy = false);
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
      // Sukses dari sheet → tutup sheet (flag dimatikan dulu supaya
      // finally tidak memanggil setSheet setelah pop).
      if (_formSheetOpen && sheetCtx.mounted) {
        _formSheetOpen = false;
        Navigator.of(sheetCtx).pop();
      }
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
      // Guard flag: sheet bisa di-dismiss user di tengah RPC —
      // setSheet setelah dispose melempar.
      if (mounted && _formSheetOpen) setSheet(() => _busy = false);
    }
  }

  /// Penanda sheet form dummy sedang terbuka. Dipakai _register untuk
  /// memutuskan pop + setSheet yang aman.
  bool _formSheetOpen = false;

  /// Buka bottom sheet form dummy. Mode tambah (item null) atau edit.
  Future<void> _openDummySheet({Map<String, dynamic>? item, required S s}) {
    if (item != null) {
      _fillForm(item);
    } else {
      _cancelEdit();
    }
    _nicknameError = null;
    _busy = false;
    _formSheetOpen = true;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: StatefulBuilder(
              builder: (_, setSheet) => _buildDummyForm(s, setSheet, sheetCtx),
            ),
          ),
        ),
      ),
    ).then((_) {
      _formSheetOpen = false;
      if (mounted) setState(() => _busy = false);
    });
  }

  /// Isi bottom sheet: judul + tombol X + form profil dummy.
  /// Widget SAMA (ProfileFormCard) seperti form inline lama — ukuran/
  /// behavior identik, hanya wadahnya pindah ke sheet.
  Widget _buildDummyForm(S s, StateSetter setSheet, BuildContext sheetCtx) {
    final isEdit = _editingUid != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isEdit ? '${s.dummyEdit} Dummy' : s.dummyCreateTitle,
                style: AppText.titleEmphasis,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(sheetCtx).closeButtonTooltip,
              onPressed: () {
                _cancelEdit();
                Navigator.of(sheetCtx).pop();
              },
              icon: const Icon(Icons.close),
              color: AppTheme.textSecondary,
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          s.dummyRegisterHint,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 10),
        ProfileFormCard(
          s: s,
          nicknameCtrl: _nickCtrl,
          nicknameFocus: _nicknameFocus,
          nicknameError: _nicknameError,
          onNicknameChanged: (v) => _onNicknameChanged(v, setSheet),
          onNicknameSubmitted: () => _register(s, setSheet, sheetCtx),
          gender: _gender,
          onGenderChanged: (v) => setSheet(() => _gender = v),
          age: _age,
          onAgeChanged: (v) => setSheet(() => _age = v),
          country: _negara,
          onCountryChanged: (v) {
            final cities = getCitiesForCountry(v);
            setSheet(() {
              _negara = v;
              _kota = cities.isNotEmpty ? cities.first : '';
            });
          },
          city: _kota,
          onCityChanged: (v) => setSheet(() => _kota = v),
          loading: _busy,
          submitLabel: isEdit ? s.dummySaveChanges : s.dummyRegisterBtn,
          onSubmit: () => _register(s, setSheet, sheetCtx),
        ),
      ],
    );
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
          // ── Daftar akun dummy (form tambah/edit pindah ke bottom sheet) ──
          Row(
            children: [
              Text(s.dummyListTitle, style: AppText.titleEmphasis),
              Spacer(),
              Text(
                _search.isEmpty
                    ? '${_items.length}'
                    : '${_filtered.length}/${_items.length}',
                style: AppText.label.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openDummySheet(s: s),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.dummyAdd),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: AppText.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Pencarian dummy (filter lokal by nickname) ──
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v.trim()),
            style: AppText.body.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: s.searchHint,
              hintStyle:
                  AppText.body.copyWith(color: AppTheme.textSecondary),
              prefixIcon:
                  Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 0),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppTheme.bgCard,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
          else if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _items.isEmpty ? s.dummyEmpty : s.dummySearchEmpty,
                  style: AppText.bodySmall,
                ),
              ),
            )
          else
            ..._filtered.map((item) => _itemCard(item, s)),
        ],
      ),
    );
  }

  /// Dialog info jadwal AI dummy (dari cron ai_presence_tick).
  void _showScheduleInfo(Map<String, dynamic> item, S s) {
    final nickname = item['nickname'] as String? ?? '';
    final status = item['status'] as String? ?? 'offline';
    final hours = _DummyAiSheetState._parseHours(item['ai_active_hours']);
    final summary = _DummyAiSheetState._hoursSummary(hours);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.dummyAiScheduleTitle} — $nickname'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${s.dummyScheduleStatusNow}: ', style: AppText.body),
                Text(status, style: AppText.bodyStrong),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hours.isEmpty
                  ? s.dummyScheduleAlwaysOn
                  : '${s.dummyAiScheduleTitle}: $summary WIB',
              style: AppText.body,
            ),
            const SizedBox(height: 8),
            Text(
              s.dummyAiScheduleDesc,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnOk),
          ),
        ],
      ),
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
    // Profesi dari ai_persona (data, tampil apa adanya). Dipadatkan:
    // potong catatan kurung (RAHASIA/JADWAL) supaya muat satu baris.
    final rawProfession =
        ((item['ai_persona'] as Map?)?['profession'] as String?)?.trim() ?? '';
    final profession = rawProfession.split('(').first.trim();
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
                      if (profession.isNotEmpty)
                        Text(
                          profession,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppTheme.accent,
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
                // Info jadwal AI (kapan online/offline dari cron) — klik.
                // (Tanpa Spacer: Expanded kolom teks sudah mendorong tombol
                // ini ke kanan; Spacer malah memakan setengah lebar teks.)
                IconButton(
                  icon: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: s.dummyAiScheduleTitle,
                  onPressed: () => _showScheduleInfo(item, s),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Baris aksi: dropdown status + chip AI (kiri), 3 tombol ikon
            // kanan mepet tanpa celah (InkWell padding 6 — bukan IconButton
            // yang memaksa min touch-target 48).
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _statusDropdown(item, status, s),
                ),
                const SizedBox(width: 6),
                _aiChip(item, s),
                _dummyIconBtn(
                  tooltip: s.dummyEdit,
                  icon: Icons.edit_outlined,
                  color: AppTheme.textSecondary,
                  onTap: () => _openDummySheet(item: item, s: s),
                ),
                _dummyIconBtn(
                  tooltip: s.dummyChatAs,
                  icon: Icons.chat_bubble_outline,
                  color: AppTheme.primary,
                  onTap: () => _chatAs(item, s),
                ),
                _dummyIconBtn(
                  tooltip: s.dummyDelete,
                  icon: Icons.delete_outline,
                  color: AppTheme.danger,
                  onTap: () => _delete(item, s),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Dropdown status dummy (online/idle/offline) — nilai aktif langsung
  /// terlihat; ganti nilai = set status via RPC yang sama seperti chip dulu.
  Widget _statusDropdown(Map<String, dynamic> item, String current, S s) {
    const values = ['online', 'idle', 'offline'];
    final labels = [s.statusOnline, s.statusIdle, s.statusOffline];
    final safeValue = values.contains(current) ? current : 'offline';
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      isDense: true,
      style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: [
        for (var i = 0; i < values.length; i++)
          DropdownMenuItem(
            value: values[i],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(values[i]),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodySmall.copyWith(
                      color: _statusColor(values[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null && v != current) _setStatus(item, v, s);
      },
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

  /// Tombol ikon kartu dummy yang mepet: InkWell padding 4 (total 28px),
  /// tanpa min touch-target 48 ala IconButton. Visual ikon 20, jarak
  /// antar-ikon = 8px.
  Widget _dummyIconBtn({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Future<void> _openAiSheet(Map<String, dynamic> item, S s) async {    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Batasi 90% layar + SafeArea atas supaya sheet panjang tidak
      // overlap area sinyal/status bar HP.
      builder: (_) => SafeArea(
        top: true,
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: _DummyAiSheet(item: item),
        ),
      ),
    );
    if (saved == true) await _load();
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

  /// Preset model LLM per dummy. Nilai = id model persis seperti yang
  /// dipakai edge function ai-reply (routing: mimo-*-free → Zen gratis).
  /// null = "Ikuti global" (default_model di ai_provider_config).
  static const List<(String, String?)> kAiModelOptions = [
    ('Ikuti global', null),
    ('Mimo 2.5 (gratis, Zen)', 'mimo-v2.5-free'),
    ('GLM 5.3 Flash (B.AI)', 'glm-5.3-flash'),
    ('Nemotron 3 Ultra free (OpenRouter)', 'nvidia/nemotron-3-ultra-550b-a55b:free'),
  ];

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
  bool _noRate = false;
  late final TextEditingController _maxRateCtrl;
  late final TextEditingController _minRateCtrl;
  // Model LLM per-dummy: 0 = ikuti global, 1..N = preset di kAiModelOptions.
  int _modelSel = 0;
  late final TextEditingController _modelCustomCtrl;
  late bool _schedAuto;
  late List<int> _hours;
  bool _schedBusy = false;
  late final TextEditingController _personalityCtrl;
  late final TextEditingController _toneCtrl;
  late final TextEditingController _extraCtrl;
  bool _busy = false;
  // Toggle instan: true saat RPC apply berjalan; perubahan yang masuk
  // selama itu ditandai dirty lalu dijalankan sekali setelahnya.
  bool _applying = false;
  bool _applyDirty = false;

  @override
  void initState() {
    super.initState();
    final persona =
        (widget.item['ai_persona'] as Map<dynamic, dynamic>?) ?? const {};
    _enabled = widget.item['ai_enabled'] == true;
    final g = widget.item['ai_guard_enabled'];
    _guardSel = g == true ? 1 : g == false ? 2 : 0;
    _schedAuto = (widget.item['ai_schedule_auto'] as bool?) ?? true;
    _noRate = (widget.item['ai_no_rate_limit'] as bool?) ?? false;
    _maxRateCtrl = TextEditingController(
      text: (widget.item['ai_max_replies'] as num?)?.toString() ?? '',
    );
    _minRateCtrl = TextEditingController(
      text: (widget.item['ai_min_interval'] as num?)?.toString() ?? '',
    );
    _hours = _parseHours(widget.item['ai_active_hours']);
    _personalityCtrl = TextEditingController(text: '${persona['personality'] ?? ''}');
    _toneCtrl = TextEditingController(text: '${persona['tone'] ?? ''}');
    _extraCtrl = TextEditingController(text: '${persona['extra_prompt'] ?? ''}');
    // Model: cocokkan ai_model sekarang ke preset; kalau tidak cocok
    // (custom id), masukkan ke kolom custom.
    _modelCustomCtrl = TextEditingController();
    final curModel = (widget.item['ai_model'] as String?)?.trim();
    _modelSel = 0;
    if (curModel != null && curModel.isNotEmpty) {
      for (var i = 1; i < kAiModelOptions.length; i++) {
        if (kAiModelOptions[i].$2 == curModel) {
          _modelSel = i;
          break;
        }
      }
      if (_modelSel == 0) _modelCustomCtrl.text = curModel;
    }
  }

  @override
  void dispose() {
    _personalityCtrl.dispose();
    _toneCtrl.dispose();
    _extraCtrl.dispose();
    _maxRateCtrl.dispose();
    _minRateCtrl.dispose();
    _modelCustomCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _applyAi(showResult: true);
  }

  /// Nilai persona dari kolom teks (kepribadian/gaya/prompt tambahan).
  Map<String, dynamic> _personaMap() => {
        if (_personalityCtrl.text.trim().isNotEmpty)
          'personality': _personalityCtrl.text.trim(),
        if (_toneCtrl.text.trim().isNotEmpty) 'tone': _toneCtrl.text.trim(),
        if (_extraCtrl.text.trim().isNotEmpty)
          'extra_prompt': _extraCtrl.text.trim(),
      };

  /// Nilai model dari chip/custom (logika sama dengan tombol simpan).
  String _modelValue() {
    if (_modelSel == 0 && _modelCustomCtrl.text.trim().isEmpty) return 'NULL';
    if (_modelSel == -1 || _modelSel >= kAiModelOptions.length) {
      return _modelCustomCtrl.text.trim().isEmpty
          ? 'NULL'
          : _modelCustomCtrl.text.trim();
    }
    return kAiModelOptions[_modelSel].$2 ?? 'NULL';
  }

  /// Terapkan SEMUA setting saat ini ke server. Dipakai toggle instan
  /// (diam-diam, tanpa tutup sheet) maupun tombol Simpan (dengan hasil).
  /// Persona selalu dikirim dari kolom teks supaya tidak ter-wipe oleh RPC
  /// (server menimpa ai_persona dengan p_persona apa pun isinya).
  Future<void> _applyAi({bool showResult = false}) async {
    final s = context.read<LocaleProvider>().s;
    if (!_isAdminSession()) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.dummyNeedAdmin)));
      return;
    }
    if (_applying) {
      _applyDirty = true;
      return;
    }
    _applying = true;
    if (showResult) setState(() => _busy = true);
    try {
      final svc = AdminService(SupabaseConfig.client);
      final guardValue = _guardSel == 0 ? null : _guardSel == 1;
      await svc.setDummyAi(
        widget.item['uid'] as String,
        _enabled,
        _personaMap(),
        scheduleAuto: _schedAuto,
        guardEnabled: guardValue,
        noRateLimit: _noRate,
        maxReplies: int.tryParse(_maxRateCtrl.text.trim()),
        minInterval: int.tryParse(_minRateCtrl.text.trim()),
        activeHours: _hours.toList()..sort(),
        model: _modelValue(),
      );
      widget.item['ai_enabled'] = _enabled;
      widget.item['ai_guard_enabled'] = guardValue;
      widget.item['ai_no_rate_limit'] = _noRate;
      widget.item['ai_max_replies'] = int.tryParse(_maxRateCtrl.text.trim());
      widget.item['ai_min_interval'] = int.tryParse(_minRateCtrl.text.trim());
      widget.item['ai_active_hours'] = _hours.toList()..sort();
      widget.item['ai_schedule_auto'] = _schedAuto;
      final mv = _modelValue();
      widget.item['ai_model'] = mv == 'NULL' ? null : mv;
      if (!mounted) return;
      if (showResult) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(s.dummyAiSaved)));
      }
    } catch (e) {
      dlog('[DUMMY] apply AI error: $e');
      if (!mounted) return;
      if (showResult) setState(() => _busy = false);
      final msg = '$e'.replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${s.dummyAiSaveFail}: $msg')));
    } finally {
      _applying = false;
      if (_applyDirty) {
        _applyDirty = false;
        if (mounted) unawaited(_applyAi());
      }
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Handle + judul ──
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${s.dummyAiTitle} — $nickname',
                    style: AppText.title,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
            Text(
              s.dummyAiDesc,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            // ── 1 · Status (WAJIB — satu-satunya yang harus disentuh) ──
            _sectionCard(
              title: s.dummyAiSectionStatus,
              badge: s.dummyAiBadgeRequired,
              badgeOn: true,
              desc: s.dummyAiStatusDesc,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _enabled,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  unawaited(_applyAi());
                },
                title: Text(s.dummyAiEnabledLabel, style: AppText.bodyStrong),
                activeThumbColor: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            // ── 2 · Kepribadian (OPSIONAL — kosong = otomatis) ──
            _sectionCard(
              title: s.dummyAiSectionPersona,
              badge: s.dummyAiBadgeOptional,
              badgeOn: false,
              desc: s.dummyAiPersonaDesc,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(s.btnSave),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── 3 · Lanjutan (dilipat — jarang diubah) ──
            _sectionCard(
              title: s.dummyAiSectionAdvanced,
              badge: s.dummyAiBadgeAuto,
              badgeOn: false,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: false,
                shape: const Border(),
                title: Text(
                  s.dummyAiInstantHint,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                children: [
                  _subBlock(
                    label: s.aiGlobalGuardTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<int>(
                          segments: [
                            ButtonSegment(value: 0, label: Text(s.aiGuardGlobal)),
                            ButtonSegment(value: 1, label: Text(s.aiGuardOn)),
                            ButtonSegment(value: 2, label: Text(s.aiGuardOff)),
                          ],
                          selected: {_guardSel},
                          onSelectionChanged: (v) {
                            setState(() => _guardSel = v.first);
                            unawaited(_applyAi());
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.dummyAiGuardHint,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  // ── Model LLM per-dummy ──
                  _subBlock(
                    label: s.dummyAiModelTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: [
                            for (var i = 0; i < kAiModelOptions.length; i++)
                              ChoiceChip(
                                label: Text(
                                  i == 0
                                      ? 'Global'
                                      : kAiModelOptions[i].$1.split(' (').first,
                                  style: AppText.bodySmall,
                                ),
                                selected: _modelSel == i &&
                                    _modelCustomCtrl.text.isEmpty,
                                onSelected: (_) {
                                  setState(() {
                                    _modelSel = i;
                                    _modelCustomCtrl.clear();
                                  });
                                  unawaited(_applyAi());
                                },
                              ),
                            ChoiceChip(
                              label: Text(s.dummyAiModelCustom,
                                  style: AppText.bodySmall),
                              selected: _modelCustomCtrl.text.isNotEmpty,
                              onSelected: (_) =>
                                  setState(() => _modelSel = -1),
                            ),
                          ],
                        ),
                        if (_modelSel == -1 ||
                            _modelCustomCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          TextField(
                            controller: _modelCustomCtrl,
                            style: AppText.body,
                            decoration: InputDecoration(
                              labelText: s.dummyAiModelCustom,
                              helperText: 'cth: mimo-v2.5-free',
                              helperMaxLines: 2,
                            ),
                            onChanged: (_) => setState(() => _modelSel = -1),
                            onSubmitted: (_) => unawaited(_applyAi()),
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            s.dummyAiModelDesc,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  // ── Rate limit per-dummy ──
                  _subBlock(
                    label: s.dummyRateTitle,
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _noRate,
                          onChanged: (v) {
                            setState(() => _noRate = v);
                            unawaited(_applyAi());
                          },
                          title:
                              Text(s.dummyRateUnlimited, style: AppText.body),
                          activeThumbColor: AppTheme.primary,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _maxRateCtrl,
                                enabled: !_noRate,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: AppText.body,
                                decoration: InputDecoration(
                                  labelText: s.dummyRateMax,
                                  helperText: s.dummyRateGlobalHint,
                                  helperMaxLines: 2,
                                ),
                                onSubmitted: (_) => unawaited(_applyAi()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _minRateCtrl,
                                enabled: !_noRate,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: AppText.body,
                                decoration: InputDecoration(
                                    labelText: s.dummyRateMin),
                                onSubmitted: (_) => unawaited(_applyAi()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  // ── Jadwal kehadiran AI ──
                  // Cronjob online/idle/offline mengikuti jam aktif; offline =
                  // AI tidak membalas sama sekali. Jadwal dari kebiasaan chat.
                  _subBlock(
                    label: s.dummyAiScheduleTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _schedAuto,
                          onChanged: (v) {
                            setState(() => _schedAuto = v);
                            unawaited(_applyAi());
                          },
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
                        const SizedBox(height: 8),
                        Text(
                          _hours.isEmpty
                              ? s.dummyAiScheduleEmpty
                              : '${_hoursSummary(_hours)} WIB',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ── Editor grid 24 jam: pilih jam online ──
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (int h = 0; h < 24; h++)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _hours.contains(h)
                                        ? _hours.remove(h)
                                        : _hours.add(h);
                                  });
                                  unawaited(_applyAi());
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _hours.contains(h)
                                        ? AppTheme.primary
                                            .withValues(alpha: 0.15)
                                        : AppTheme.bgInput,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _hours.contains(h)
                                          ? AppTheme.primary
                                          : AppTheme.divider,
                                      width: _hours.contains(h) ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    h.toString().padLeft(2, '0'),
                                    style: AppText.label.copyWith(
                                      color: _hours.contains(h)
                                          ? AppTheme.primary
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.dummyHoursHint,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _schedBusy ? null : _autoSchedule,
                          icon: _schedBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(s.dummyAiScheduleAuto),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoSchedule() async {
    final s = context.read<LocaleProvider>().s;
    if (!_isAdminSession()) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.dummyNeedAdmin)));
      return;
    }
    setState(() => _schedBusy = true);
    try {
      final svc = AdminService(SupabaseConfig.client);
      final hours = await svc.autoScheduleAi(widget.item['uid'] as String);
      if (!mounted) return;
      setState(() {
        _schedBusy = false;
        _hours = hours;
      });
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
        ..showSnackBar(SnackBar(content: Text(s.dummyAiSaveFail)));
    }
  }

  /// Kartu section sheet AI: judul + badge + deskripsi + isi.
  Widget _sectionCard({
    required String title,
    String? badge,
    bool badgeOn = false,
    String? desc,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: AppText.bodyStrong),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeOn
                        ? AppTheme.primary
                        : AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: AppText.label.copyWith(
                      color: badgeOn ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (desc != null) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              style:
                  AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  /// Sub-blok di dalam section Lanjutan: label kecil + isi.
  Widget _subBlock({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
