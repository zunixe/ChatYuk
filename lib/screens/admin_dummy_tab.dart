import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/profile_form_card.dart';
import '../providers/locale_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap "masuk dummy")
/// — kalau tidak, semua RPC admin melempar 'Unauthorized' (P0001).
/// Cek di client supaya pesannya jelas; server tetap sumber kebenaran.
bool _isAdminSession() =>
    AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

/// Port Dart dari sleepHours/hashInt edge function (ai-helpers.ts):
/// `| 0` JS = 32-bit wrap → `.toSigned(32)`. HARUS identik supaya chip
/// Tidur/Bangun di kartu sama dengan gate balasan di server.
int _sleepHash(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)).toSigned(32);
  }
  return h.abs();
}

({int sleepHour, int wakeHour}) _sleepSpec(String uid, String dateWib) {
  final h = _sleepHash('$uid|$dateWib|sleep');
  return (sleepHour: 20 + (h % 4), wakeHour: 4 + ((h ~/ 4) % 3));
}

/// True bila dummy sedang jam tidur menurut jadwal server (WIB).
bool _isAsleepNow(String uid, DateTime now) {
  final wib = now.toUtc().add(const Duration(hours: 7));
  final date =
      '${wib.year.toString().padLeft(4, '0')}-${wib.month.toString().padLeft(2, '0')}-${wib.day.toString().padLeft(2, '0')}';
  final spec = _sleepSpec(uid, date);
  return wib.hour >= spec.sleepHour || wib.hour < spec.wakeHour;
}

/// ai_wake_until masih berlaku → dibangunkan paksa (balasan + online).
bool _isWakeActive(Map<String, dynamic> item, DateTime now) {
  final raw = '${item['ai_wake_until'] ?? ''}';
  if (raw.isEmpty) return false;
  final until = DateTime.tryParse(raw);
  return until != null && until.isAfter(now);
}

/// Jam:menit WIB dari ISO string — netral bahasa (netral di semua locale).
String _wibClock(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final wib = dt.toUtc().add(const Duration(hours: 7));
  return '${wib.hour.toString().padLeft(2, '0')}:${wib.minute.toString().padLeft(2, '0')}';
}

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

  // Warna status dgn tambahan 'invisible' (khas admin — bukan status app).
  Color _statusColor(String status) =>
      status == 'invisible' ? const Color(0xFF7E57C2) : AppTheme.statusColor(status);

  String _genderLabel(S s, String? gender) =>
      gender == 'female' ? s.labelGenderFemale : s.labelGenderMale;

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
          return _itemCard(_filtered[i - _headerCount], s);
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

  /// Sheet riwayat story harian dummy (biasa). Menampilkan N hari terakhir
  /// + status terisi/kosong supaya ketahuan hari mana yang belum
  /// ke-generate. Expert tidak punya story (server tak generate).
  void _showDummyStories(Map<String, dynamic> item, S s) {
    final nickname = item['nickname'] as String? ?? '';
    final uid = item['uid'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (ctx, scrollCtrl) {
            return FutureBuilder<Map<String, dynamic>>(
              future: _svc.getDummyStories(uid, days: 14),
              builder: (ctx, snap) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_stories_outlined,
                                  size: 20, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${s.dummyStoryList} — $nickname',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.title,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (snap.data?['story_expected'] == false)
                                ? s.dummyStoryNotExpected
                                : s.dummyStoryListDesc,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1),
                    Expanded(
                      child: snap.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : snap.hasError
                              ? Center(
                                  child: Text(
                                    '${s.dummyStoryLoadFail}: ${snap.error}',
                                    style: AppText.bodySmall.copyWith(
                                      color: AppTheme.danger,
                                    ),
                                  ),
                                )
                              : _storyList(
                                   snap.data ?? const {}, s, scrollCtrl, item),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _generateDummyStory(
    Map<String, dynamic> item,
    S s,
    String storyDate,
  ) async {
    final uid = item['uid'] as String? ?? '';
    if (uid.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.dummyStoryGenerating)),
    );
    try {
      final result = await _svc.generateDummyStory(
        uid,
        storyDate: storyDate,
      );
      if (!mounted) return;
      final generated = (result['generated'] as List?)?.contains(uid) == true;
      final skipped = (result['skipped'] as List?)?.contains(uid) == true;
      final failed = (result['failed'] as List?)?.contains(uid) == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (generated || skipped) && !failed
                ? s.dummyStoryGenerated
                : s.dummyStoryGenerateFail,
          ),
        ),
      );
      if (generated || skipped) _showDummyStories(item, s);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.dummyStoryGenerateFail)),
      );
      dlog('[ADMIN] generate dummy story error: $e');
    }
  }

  Widget _storyList(
    Map<String, dynamic> data,
    S s,
    ScrollController scrollCtrl,
    Map<String, dynamic> item,
  ) {
    final days = (data['days'] as List?) ?? const [];
    if (days.isEmpty) {
      return Center(
        child: Text(s.dummyStoryEmpty, style: AppText.bodySmall),
      );
    }
    final missing =
        days.where((d) => (d as Map)['has_story'] != true).length;
    return ListView.separated(
      controller: scrollCtrl,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: days.length + 1,
      separatorBuilder: (_, i) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i == 0) {
          if (missing == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.dummyStoryMissingCount.replaceAll('%s', '$missing'),
                    style: AppText.caption.copyWith(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
          );
        }
        final d = Map<String, dynamic>.from(days[i - 1] as Map);
        final has = d['has_story'] == true;
        final story = d['story'];
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    has ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: has ? AppTheme.primary : AppTheme.danger,
                  ),
                  const SizedBox(width: 8),
                   Text('${d['date']}', style: AppText.bodyStrong),
                   const Spacer(),
                   if (!has)
                     IconButton(
                       icon: Icon(
                         Icons.auto_awesome,
                         size: 18,
                         color: AppTheme.primary,
                       ),
                       tooltip: s.dummyStoryGenerate,
                       onPressed: () =>
                           _generateDummyStory(item, s, '${d['date']}'),
                     ),
                   Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (has ? AppTheme.primary : AppTheme.danger)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      has ? s.dummyStoryFilled : s.dummyStoryMissing,
                      style: AppText.caption.copyWith(
                        color: has ? AppTheme.primary : AppTheme.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (has && story != null) ...[
                const SizedBox(height: 6),
                Text(
                  _storySummary(story),
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Ringkas story (jsonb) jadi satu kalimat untuk ditampilkan.
  String _storySummary(dynamic story) {
    if (story is String) return story;
    if (story is Map) {
      for (final k in ['summary', 'work', 'place', 'problem', 'hangout']) {
        final v = story[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return story.values
          .whereType<String>()
          .where((v) => v.trim().isNotEmpty)
          .join(' · ');
    }
    return '$story';
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodyStrong,
                            ),
                          ),
                          // Badge EXPERT: dari kolom `kind` (bukan nickname).
                          if ((item['kind'] as String? ?? 'regular') ==
                              'expert') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 11,
                                    color: AppTheme.accent,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    s.dummyKindExpert,
                                    style: AppText.caption.copyWith(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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
                      _sleepChip(item, s),
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
                // Story harian — HANYA dummy biasa (expert tak punya story).
                if ((item['kind'] as String? ?? 'regular') == 'regular')
                  IconButton(
                    icon: Icon(
                      Icons.auto_stories_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    tooltip: s.dummyStoryList,
                    onPressed: () => _showDummyStories(item, s),
                  ),
              ],
            ),
            SizedBox(height: 8),
            // Baris aksi: dropdown status + chip AI (kiri), 4 tombol ikon
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
                  tooltip: s.dummyWake,
                  icon: _isWakeActive(item, DateTime.now())
                      ? Icons.alarm_on
                      : Icons.alarm_add_outlined,
                  color: _isWakeActive(item, DateTime.now())
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  onTap: () => _wake(item, s),
                ),
                _dummyIconBtn(
                  tooltip: s.statusInvisible,
                  icon: status == 'invisible'
                      ? Icons.visibility_off
                      : Icons.visibility_off_outlined,
                  color: status == 'invisible'
                      ? _statusColor('invisible')
                      : AppTheme.textSecondary,
                  onTap: () => _setStatus(
                    item,
                    status == 'invisible' ? 'online' : 'invisible',
                    s,
                  ),
                ),
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

  /// Dropdown status dummy (online/idle/offline/invisible) — nilai aktif
  /// langsung terlihat; ganti nilai = set status via RPC yang sama seperti
  /// chip dulu. Invisible = user lain lihat offline & tidak muncul di
  /// daftar online (cron AI tidak menimpa).
  Widget _statusDropdown(Map<String, dynamic> item, String current, S s) {
    const values = ['online', 'idle', 'offline', 'invisible'];
    final labels = [
      s.statusOnline,
      s.statusIdle,
      s.statusOffline,
      s.statusInvisible,
    ];
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

  /// Chip AI dummy: ON = aksen solid + ikon terisi putih, OFF = abu
  /// netral + ikon outline — beda tegas sekilas (bukan samar).
  /// Tap = buka sheet persona.
  Widget _aiChip(Map<String, dynamic> item, S s) {
    final aiOn = item['ai_enabled'] == true;
    final offColor = AppTheme.textSecondary;
    return InkWell(
      onTap: () => _openAiSheet(item, s),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: aiOn ? AppTheme.accent : offColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: aiOn
              ? null
              : Border.all(color: offColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              aiOn ? Icons.smart_toy : Icons.smart_toy_outlined,
              size: 13,
              color: aiOn ? Colors.white : offColor,
            ),
            const SizedBox(width: 4),
            Text(
              s.dummyAiChip,
              style: AppText.label.copyWith(
                color: aiOn ? Colors.white : offColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chip Tidur/Bangun di kartu dummy — bedakan "AI error" vs "lagi tidur":
  /// Bangun paksa (wake aktif, teks + jam s/d) / Bangun (jam melek) / Tidur.
  /// Dihitung dari jam tidur server + ai_wake_until (konsisten dgn gate).
  /// Kalau ai_active_hours mencakup jam sekarang → paksa bangun (online 24j).
  Widget _sleepChip(Map<String, dynamic> item, S s) {
    final now = DateTime.now();
    final wakeActive = _isWakeActive(item, now);
    // Cek apakah jam sekarang ada di ai_active_hours → dummy bangun.
    final wib = now.toUtc().add(const Duration(hours: 7));
    final activeHours = _DummyAiSheetState._parseHours(item['ai_active_hours']);
    final inActiveHours = activeHours.contains(wib.hour);
    final asleep =
        !wakeActive && !inActiveHours && _isAsleepNow('${item['uid'] ?? ''}', now);
    final label = wakeActive
        ? '${s.dummyAwake} • ${s.dummyWakeUntil.replaceFirst('%s', _wibClock('${item['ai_wake_until'] ?? ''}'))}'
        : asleep
            ? s.dummyAsleep
            : s.dummyAwake;
    final color = asleep ? AppTheme.textSecondary : AppTheme.online;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            asleep ? Icons.bedtime_outlined : Icons.alarm_on_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// Tombol ikon kartu dummy yang mepet: InkWell padding 4 (total 28px),
  /// tanpa min touch-target 48 ala IconButton. Visual ikon 20, jarak
  /// antar-ikon = 8px.
  Widget _dummyIconBtn({    required String tooltip,
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
  bool _photosEnabled = true;
  late final TextEditingController _maxRateCtrl;
  late final TextEditingController _minRateCtrl;
  // Default global (AI Bot) untuk hint: null = belum dimuat/gagal.
  int? _globalMax;
  int? _globalMin;
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
    _photosEnabled = (widget.item['ai_photos_enabled'] as bool?) ?? true;
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
    // Model LLM selalu ikut global — tidak ada override per-dummy.
    // Default global (AI Bot) untuk hint rate-limit.
    unawaited(_loadGlobalRate());
  }

  /// Muat batas global AI Bot (sekali) supaya hint kolom rate-limit bisa
  /// menampilkan angka default yang berlaku saat kolom dikosongkan.
  Future<void> _loadGlobalRate() async {
    try {
      final res = await context.read<AdminProvider>().getAiSettings();
      if (!mounted) return;
      setState(() {
        _globalMax = (res['ai_max_replies_per_hour'] as num?)?.toInt();
        _globalMin = (res['ai_min_interval_sec'] as num?)?.toInt();
      });
    } catch (_) {
      // Gagal = hint tetap generik (tanpa angka).
    }
  }

  /// Hint kolom rate-limit: tampilkan angka global yang berlaku bila
  /// dikosongkan; fallback ke hint generik selama global belum dimuat.
  String _rateHint() {
    final m = _globalMax;
    final j = _globalMin;
    final s = context.read<LocaleProvider>().s;
    if (m != null && j != null) return s.dummyRateGlobalHintVals(m, j);
    return s.dummyRateGlobalHint;
  }

  @override
  void dispose() {
    _personalityCtrl.dispose();
    _toneCtrl.dispose();
    _extraCtrl.dispose();
    _maxRateCtrl.dispose();
    _minRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _applyAi(showResult: true);
  }

  /// Nilai persona dari kolom teks (kepribadian/gaya/prompt tambahan).
  /// Flag non-teks (long_answers/diagrams/charts/no_images/dsb) dipertahankan
  /// dari ai_persona lama supaya tidak ter-wipe oleh RPC yang menimpa penuh.
  Map<String, dynamic> _personaMap() {
    final prev = (widget.item['ai_persona'] as Map?) ?? const {};
    return {
      if (_personalityCtrl.text.trim().isNotEmpty)
        'personality': _personalityCtrl.text.trim(),
      if (_toneCtrl.text.trim().isNotEmpty) 'tone': _toneCtrl.text.trim(),
      if (_extraCtrl.text.trim().isNotEmpty)
        'extra_prompt': _extraCtrl.text.trim(),
      for (final k in const [
        'profession',
        'profession_skills',
        'greeting',
        'long_answers',
        'diagrams',
        'charts',
        'no_images',
        'market_data',
      ])
        if (prev[k] != null) k: prev[k],
    };
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
      final svc = context.read<AdminProvider>();
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
        photosEnabled: _photosEnabled,
      );
      widget.item['ai_enabled'] = _enabled;
      widget.item['ai_guard_enabled'] = guardValue;
      widget.item['ai_no_rate_limit'] = _noRate;
      widget.item['ai_max_replies'] = int.tryParse(_maxRateCtrl.text.trim());
      widget.item['ai_min_interval'] = int.tryParse(_minRateCtrl.text.trim());
      widget.item['ai_active_hours'] = _hours.toList()..sort();
      widget.item['ai_schedule_auto'] = _schedAuto;
      widget.item['ai_photos_enabled'] = _photosEnabled;
      widget.item['ai_persona'] = _personaMap();
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
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: [
                              ButtonSegment(
                                  value: 0,
                                  label: Text(s.aiGuardGlobal,
                                      style: AppText.label)),
                              ButtonSegment(
                                  value: 1,
                                  label:
                                      Text(s.aiGuardOn, style: AppText.label)),
                              ButtonSegment(
                                  value: 2,
                                  label:
                                      Text(s.aiGuardOff, style: AppText.label)),
                            ],
                            selected: {_guardSel},
                            onSelectionChanged: (v) {
                              setState(() => _guardSel = v.first);
                              unawaited(_applyAi());
                            },
                          ),
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
                                  helperText: _rateHint(),
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
                                  labelText: s.dummyRateMin,
                                  helperText: _rateHint(),
                                  helperMaxLines: 2,
                                ),
                                onSubmitted: (_) => unawaited(_applyAi()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),
                  // ── Kirim foto AI ──
                  _subBlock(
                    label: s.dummyPhotosTitle,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _photosEnabled,
                          onChanged: (v) {
                            setState(() => _photosEnabled = v);
                            unawaited(_applyAi());
                          },
                          title: Text(
                            s.dummyPhotosLabel,
                            style: AppText.bodySmall,
                          ),
                          activeThumbColor: AppTheme.primary,
                        ),
                        Text(
                          s.dummyPhotosDesc,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
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
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _hours = List.generate(24, (i) => i);
                                });
                                unawaited(_applyAi());
                              },
                              child: Text(s.dummyHoursSelectAll,
                                  style: AppText.label),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {
                                setState(() => _hours.clear());
                                unawaited(_applyAi());
                              },
                              child: Text(s.dummyHoursClearAll,
                                  style: AppText.label),
                            ),
                          ],
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
      final svc = context.read<AdminProvider>();
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
