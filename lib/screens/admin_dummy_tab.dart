import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../config/regions.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../core/admin_gate.dart';
import '../core/admin_err.dart';
import '../core/cache/message_cache.dart';
import '../providers/auth_provider.dart';
import 'admin_dummy/widgets/dummy_ai_sheet.dart';
import 'admin_dummy/widgets/dummy_story_sheet.dart';
import 'admin_dummy/widgets/dummy_card.dart';
import 'admin_dummy/widgets/dummy_form_sheet.dart';
import '../providers/locale_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap "masuk dummy")
/// — kalau tidak, semua RPC admin melempar 'Unauthorized' (P0001).
/// Cek di client supaya pesannya jelas; server tetap sumber kebenaran.
bool _isAdminSession() =>
    AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);


/// Filter daftar dummy (pure — dipakai `_filtered` + unit test).
/// - [search]: cocokkan substring nickname (case-insensitive). Kosong = lolos.
/// - [kind]: `null` = semua tipe; `'regular'`/`'expert'` = hanya tipe itu.
///   Nilai item yang tak punya/missing `kind` dianggap `'regular'`.
List<Map<String, dynamic>> filterDummies(
  List<Map<String, dynamic>> items, {
  String search = '',
  String? kind,
}) {
  final q = search.toLowerCase();
  return items.where((m) {
    if (kind != null && (m['kind'] as String? ?? 'regular') != kind) {
      return false;
    }
    if (q.isEmpty) return true;
    return (m['nickname'] as String? ?? '').toLowerCase().contains(q);
  }).toList();
}

/// Tab Dummy di Admin Panel — buat/daftarkan akun dummy (anonymous, tanpa
/// email/password) dengan gender/umur/negara/kota, chat sebagai akun itu
/// (swap sesi tanpa login manual), set status online/idle/offline,
/// dan hapus akun beserta history chat.
class AdminDummyTab extends StatefulWidget {
  const AdminDummyTab({super.key});

  @override
  State<AdminDummyTab> createState() => _AdminDummyTabState();
}

class _AdminDummyTabState extends State<AdminDummyTab>
    with WidgetsBindingObserver {
  AdminProvider get _svc => context.read<AdminProvider>();
  final _nickCtrl = TextEditingController();
  final _nicknameFocus = FocusNode();
  String? _nicknameError;
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  String _search = '';
  /// Filter tipe akun: null = semua, 'regular' = biasa, 'expert' = expert.
  /// Diisi dari kolom `kind` (RPC admin_list_dummies), bukan nickname.
  String? _kindFilter;
  String _gender = 'male';
  int _age = 25;
  String _negara = 'Indonesia';
  String _kota = 'Jakarta';
  String? _editingUid;
  bool _busy = false;
  bool _loading = true;
  /// Kategori kegagalan (bukan teks mentah — lihat lib/core/admin_err.dart).
  AdminErrKind? _error;
  List<Map<String, dynamic>> _items = [];
  Timer? _refreshTimer;
  // Paginasi server (admin_list_dummies_page) — cegah tarik seluruh tabel.
  static const int _pageSize = 50;
  bool _hasMore = true;
  bool _fetchingMore = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scrollCtrl.addListener(_onScroll);
    // Polling 30 dtk (dulu 15 dtk) — cukup untuk badge unread per dummy
    // tanpa membebani DB/rebuild berlebihan. Lewati kalau sudah load-more
    // (jangan reset paginasi yang sedang di-scroll).
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (_items.length > _pageSize) return;
      _load(silent: true);
    });
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  /// Muat halaman dummy berikutnya (append).
  Future<void> _loadMore() async {
    if (_fetchingMore || !_hasMore || _loading) return;
    _fetchingMore = true;
    try {
      final res = await _svc.listDummiesPage(
        limit: _pageSize,
        offset: _items.length,
      );
      final more = ((res['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? _total;
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...more];
        _total = total;
        _hasMore = _items.length < total && more.isNotEmpty;
      });
    } catch (e) {
      dlog('[DUMMY] loadMore error: $e');
    } finally {
      _fetchingMore = false;
    }
  }

  /// App di-background → stop polling (hemat baterai & beban DB).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_refreshTimer == null) {
        _load(silent: true);
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted) return;
          if (_items.length > _pageSize) return;
          _load(silent: true);
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _nickCtrl.dispose();
    _nicknameFocus.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _svc.listDummiesPage(limit: _pageSize, offset: 0);
      final items = ((res['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = total;
        _hasMore = items.length < total;
        _loading = false;
      });
      // Simpan cache disk (tahan offline) — kunci per-uid admin.
      if (items.isNotEmpty) {
        MessageCache.instance
            .saveRawList('admin_dummy_list', items);
      }
    } catch (e) {
      dlog('[DUMMY] list error: $e');
      if (!mounted) return;
      // Refresh senyap (timer): jangan timpa list/badge yang sudah tampil
      // dengan error transien — cukup lewati sampai tick berikutnya.
      if (silent) return;
      // Offline & belum ada data → coba tampilkan cache disk dulu.
      if (_items.isEmpty) {
        try {
          final cached = await MessageCache.instance.loadRawList(
            'admin_dummy_list',
          );
          if (cached.isNotEmpty && mounted) {
            setState(() {
              _items = cached;
              _total = cached.length;
              _loading = false;
            });
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        // Kategori ramah; detail exception hanya ke dlog.
        _error = classifyAdminError(e);
        _loading = false;
      });
    }
  }

  /// Daftar dummy terfilter pencarian (by nickname, case-insensitive)
  /// dan filter tipe (`kind`: regular/expert). Query kosong + filter
  /// null = semua item.
  List<Map<String, dynamic>> get _filtered =>
      filterDummies(_items, search: _search, kind: _kindFilter);

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
    if (_guardOffline(s)) return;
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
              builder: (_, setSheet) => DummyFormSheet(
                s: s,
                isEdit: _editingUid != null,
                nickCtrl: _nickCtrl,
                nicknameFocus: _nicknameFocus,
                nicknameError: _nicknameError,
                gender: _gender,
                age: _age,
                country: _negara,
                city: _kota,
                busy: _busy,
                onClose: () {
                  _cancelEdit();
                  Navigator.of(sheetCtx).pop();
                },
                onNicknameChanged: (v) => _onNicknameChanged(v, setSheet),
                onNicknameSubmitted: () => _register(s, setSheet, sheetCtx),
                onGenderChanged: (v) => setSheet(() => _gender = v),
                onAgeChanged: (v) => setSheet(() => _age = v),
                onCountryChanged: (v) {
                  final cities = getCitiesForCountry(v);
                  setSheet(() {
                    _negara = v;
                    _kota = cities.isNotEmpty ? cities.first : '';
                  });
                },
                onCityChanged: (v) => setSheet(() => _kota = v),
                onSubmit: () => _register(s, setSheet, sheetCtx),
              ),
            ),
          ),
        ),
      ),
    ).then((_) {
      _formSheetOpen = false;
      if (mounted) setState(() => _busy = false);
    });
  }


  Future<void> _setStatus(Map<String, dynamic> item, String status, S s) async {
    if (_guardOffline(s)) return;
    try {
      await _svc.setDummyStatus(item['uid'] as String, status);
      await _load();
      _toast(s, s.dummyStatusSet);
    } catch (e) {
      dlog('[DUMMY] set status error: $e');
      _toast(s, s.dummySetStatusFail);
    }
  }

  /// Blokir aksi tulis saat offline (hasilnya gagal separuh jalan +
  /// membingungkan). Return true = diblokir.
  bool _guardOffline(S s) {
    bool online = true;
    try {
      online = context.read<ConnectivityProvider>().online;
    } catch (_) {}
    return blockIfOffline(
      online,
      (m) => _toast(s, m),
      message: s.adminNeedsConnection,
    );
  }

  /// Bangunkan dummy 30 menit: AI melek & membalas walau jam tidur,
  /// presence dipaksa online. Chip kartu ikut berubah (konsisten).
  Future<void> _wake(Map<String, dynamic> item, S s) async {
    if (_guardOffline(s)) return;
    try {
      await _svc.wakeDummy(item['uid'] as String);
      await _load();
      _toast(s, s.dummyWakeDone);
    } catch (e) {
      dlog('[DUMMY] wake error: $e');
      _toast(s, s.dummyWakeFail);
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
    if (_guardOffline(s)) return;
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

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        // Lazy: header tetap + daftar kartu via builder (dulu ListView biasa
        // membangun SEMUA kartu dummy sekaligus → lag saat polling 30 dtk).
        itemCount: _headerCount + _filtered.length,
        itemBuilder: (ctx, i) {
          if (i < _headerCount) return _headerChild(i, s);
          final item = _filtered[i - _headerCount];
          return DummyCard(
            item: item,
            s: s,
            onSchedule: () => showScheduleInfoDialog(context, item, s),
            onStories: () => showDummyStorySheet(context, item, s),
            onStatus: (v) => _setStatus(item, v, s),
            onWake: () => _wake(item, s),
            onToggleInvisible: () => _setStatus(
              item,
              (item['status'] as String? ?? 'offline') == 'invisible'
                  ? 'online'
                  : 'invisible',
              s,
            ),
            onEdit: () => _openDummySheet(item: item, s: s),
            onChatAs: () => _chatAs(item, s),
            onDelete: () => _delete(item, s),
            onAiSheet: () => _openAiSheet(item, s),
          );
        },
      ),
    );
  }

  /// Jumlah widget header tetap di atas daftar (dipetakan via _headerChild).
  static const int _headerCount = 9;

  Widget _headerChild(int i, S s) {
    switch (i) {
      case 0:
        // ── Daftar akun dummy (form tambah/edit pindah ke bottom sheet) ──
        return Row(
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
        );
      case 1:
        return const SizedBox(height: 8);
      case 2:
        // ── Filter tipe: Semua / Biasa / Expert (dari kolom `kind`) ──
        return SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
              value: '',
              label: Text(s.dummyKindAll, style: AppText.label),
            ),
            ButtonSegment(
              value: 'regular',
              label: Text(s.dummyKindRegular, style: AppText.label),
            ),
            ButtonSegment(
              value: 'expert',
              label: Text(s.dummyKindExpert, style: AppText.label),
            ),
          ],
          selected: {_kindFilter ?? ''},
          onSelectionChanged: (v) =>
              setState(() => _kindFilter = v.first.isEmpty ? null : v.first),
        );
      case 3:
        return const SizedBox(height: 8);
      case 4:
        // ── Pencarian dummy (filter lokal by nickname) ──
        return TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v.trim()),
          style: AppText.body.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: s.searchHint,
            hintStyle: AppText.body.copyWith(color: AppTheme.textSecondary),
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
        );
      case 5:
        return const SizedBox(height: 6);
      case 6:
        if (_loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return const SizedBox.shrink();
      case 7:
        if (!_loading && _error != null) {
          // Hanya tampil bila memang belum ada data dummy; kalau list sudah
          // terisi (cache/refresh gagal) cukup banner di atasnya.
          if (_items.isNotEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Text(
                    '${s.dummyListFail} — ${s.adminErrTextOf(_error!)}',
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(color: AppTheme.danger),
                  ),
                  if (s.adminErrHintOf(_error!).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      s.adminErrHintOf(_error!),
                      textAlign: TextAlign.center,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _load(),
                    child: Text(s.btnRetry),
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      default:
        if (!_loading && _error == null && _filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _items.isEmpty ? s.dummyEmpty : s.dummySearchEmpty,
                style: AppText.bodySmall,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
    }
  }

  /// Dialog info jadwal AI dummy (dari cron ai_presence_tick).



  Future<void> _openAiSheet(Map<String, dynamic> item, S s) {
    return showDummyAiSheet(context, item, onSaved: () => _load());
  }
}

