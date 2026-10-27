part of '../profile_screen.dart';


/// Seksi MODERASI halaman Profil: kartu moderasi (negara asal, lamaran
/// moderator, resign, konsol) + pemilih negara. Dipisah dari
/// `profile_ui2.dart` agar file tetap di bawah batas ukuran.
mixin _ProfileUiModerationMx on _ProfileBase {
  // ── Moderasi konten room publik ──────────────────────────────────────────

  /// Kartu "Moderasi": negara asal, lamaran moderator, buka konsol.
  ///
  /// Negara asal diambil dari PROFIL setiap build (`_effectiveHomeCountry`)
  /// — dulu memakai `??=` yang mengunci `null` bila profil belum termuat,
  /// sehingga namanya tidak pernah muncul walau negara sudah tersimpan.
  ///
  /// VISIBILITAS (2026-10-27): kartu hanya tampil bagi user berwenang
  /// (admin / moderator / lamaran pending) atau yang memenuhi syarat DAN
  /// slot masih terbuka. Setelah 2 slot moderator negara penuh, kartu
  /// disungui dari user lain; begitu ada moderator berhenti, kartu muncul
  /// kembali (keputusan "siapa cepat dia dapat").
  @override
  Widget _moderationSection(BuildContext context, S s) {
    final isAdmin = ref.read(authProvider.notifier).isRealAdmin;
    final home = _effectiveCountry;
    final showCard = moderationCardVisible(
      isAdmin: isAdmin,
      isModerator: _moderatingCountry.isNotEmpty,
      hasPending: _hasPending,
      countrySet: home.isNotEmpty,
      eligible: _eligible,
      slotOpen: _slotOpen,
    );
    if (!_modRoleLoaded) {
      _modRoleLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadModerationRole());
      });
    }
    if (!showCard) {
      // Hanya catatan pencabutan (jika ada) — kartu tidak relevan.
      return Column(
        children: [
          for (final rv in _revokedHistory) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.moderationRevokedNote(
                        '${rv['country'] ?? '-'}',
                        moderationDate('${rv['revoked_at'] ?? ''}') ?? '-',
                      ),
                      style: AppText.caption
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionTitle(s.moderationTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                // ── Negara asal ──
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: Text(s.moderationCountryTitle),
                  subtitle: Text(
                    home.isEmpty
                        ? s.moderationCountryHint
                        : '$home · ${s.moderationCountryHint}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickHomeCountry(context, s, isAdmin: isAdmin),
                ),
                // ── Lamaran (user biasa) / status admin ──
                if (isAdmin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(s.moderationAdminAllCountries),
                  ),
                ] else ...[
                  if (_hasPending || (_eligible && _slotOpen)) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(s.moderationApply),
                      subtitle: Text(_hasPending
                          ? s.moderationApplyPending
                          : s.moderationApplyHint),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _applyModerator(context, s, home),
                    ),
                  ],
                  if (_canOpenConsole && home.isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.back_hand_outlined),
                      title: Text(s.moderationResign),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _resignModerator(context, s),
                    ),
                  ],
                ],
                // ── Konsol: moderator negara / admin (negara dipilih di layar) ──
                if (_canOpenConsole && (home.isNotEmpty || isAdmin)) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(s.moderationOpenConsole),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openConsoleFromProfile(context, s, home),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Catatan: jabatan moderator yang dicabut karena pindah negara.
        // (Tidak ada notifikasi in-app; ini cara user menyadarinya.)
        for (final rv in _revokedHistory) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.moderationRevokedNote(
                      '${rv['country'] ?? '-'}',
                      moderationDate('${rv['revoked_at'] ?? ''}') ?? '-',
                    ),
                    style: AppText.caption
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Buka konsol moderasi dari Profil.
  ///
  /// Admin tanpa negara asal: menampilkan pilihan negara dulu (karena admin
  /// boleh membuka negara mana pun).
  Future<void> _openConsoleFromProfile(
    BuildContext context,
    S s,
    String home,
  ) async {
    var country = home;
    if (country.isEmpty) {
      final picked = await _showCountryPicker(context, s);
      if (picked == null || !context.mounted) return;
      country = picked;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ModerationScreen(country: country)),
    );
  }

  /// Ajukan diri jadi moderator negara asal (user biasa).
  ///
  /// Sejak 2026-10-27 lamaran memenuhi syarat LANGSUNG ditetapkan —
  /// popup persetujuan dulu supaya user sadar dia langsung berwenang.
  /// Slot penuh → server membalas `slots_full`.
  Future<void> _applyModerator(BuildContext context, S s, String home) async {
    if (home.isEmpty) {
      // Bukan soal media — suruh atur negara dulu (pesan lama salah konteks).
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.moderationSetCountryFirst)));
      return;
    }
    if (_hasPending) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.moderationApplyPending)));
      return;
    }
    if (!_eligible || !_slotOpen) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.moderationApplyConfirmTitle(home)),
        content: Text(
            '${s.moderationApplyConfirmBody}\n\n${s.moderationApplyConfirmNote}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.moderationApplyConfirmYes),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    final res = await ProviderScope.containerOf(context, listen: false)
        .read(chatProvider.notifier)
        .applyCountryModerator(home, reason: '');
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(moderationApplyMessage(res, s, country: home))),
    );
    unawaited(_loadModerationRole());
  }

  /// Moderator keluar sendiri — slot langsung terbuka untuk user lain.
  Future<void> _resignModerator(BuildContext context, S s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.moderationResignConfirmTitle),
        content: Text(s.moderationResignConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.moderationResign),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    final res = await ProviderScope.containerOf(context, listen: false)
        .read(chatProvider.notifier)
        .moderatorResign();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true ? s.moderationResignDone : s.errGeneric,
        ),
      ),
    );
    unawaited(_loadModerationRole());
  }

  /// Negara efektif (satu-satunya): override sesi di atas PROFIL.
  String get _effectiveCountry => effectiveCountry(
        override: _countryOverride,
        fromProfile: ref.read(authProvider).profile?.country,
      );

  /// Override sesi hasil pilih user (null = pakai nilai PROFIL).
  String? _countryOverride;

  /// Negara yang sedang dimoderasi user (kosong = bukan moderator).
  String _moderatingCountry = '';

  /// Riwayat pencabutan jabatan karena pindah negara (catatan di Profil).
  List<Map<String, dynamic>> _revokedHistory = const [];

  /// True bila user ini moderator negara (atau admin) → boleh buka konsol.
  bool _canOpenConsole = false;

  /// Memenuhi syarat lamaran (7 hari & 50 pesan publik di negaranya).
  bool _eligible = false;

  /// Slot moderator negaranya masih terbuka (maks 2 moderator per negara).
  bool _slotOpen = false;

  /// Lamaran moderator yang masih menunggu (legacy/pendamping).
  bool _hasPending = false;

  bool _modRoleLoaded = false;

  // ── Realtime slot moderator ──
  // Ping dari `moderatorSlotChanges` (event INSERT/UPDATE country_moderators)
  // → reload state → kartu tampil/hilang REALTIME (mis. moderator lain
  // mengambil slot terakhir saat panel ini sedang tampil).
  StreamSubscription<void>? _modSlotSub;
  Timer? _modSlotDebounce;

  void _startModerationRealtime() {
    if (_modSlotSub != null) return;
    _modSlotSub = ref
        .read(chatProvider.notifier)
        .moderatorSlotChanges()
        .listen((_) {
      _modSlotDebounce?.cancel();
      _modSlotDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_loadModerationRole());
      });
    });
  }

  @override
  void dispose() {
    _modSlotDebounce?.cancel();
    _modSlotSub?.cancel();
    try {
      ref.read(chatProvider.notifier).closeModeratorSlotWatch();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadModerationRole() async {
    _startModerationRealtime();
    try {
      final res = await ref
          .read(chatProvider.notifier)
          .myModerationState();
      if (!mounted || res == null) return;
      final list = res['moderates'];
      final isMod = list is List && list.isNotEmpty;
      final isAdmin = ref.read(authProvider.notifier).isRealAdmin;
      final revoked = res['revoked'];
      final pending = res['pending'];
      setState(() {
        _canOpenConsole = isMod || isAdmin;
        _moderatingCountry = isMod ? '${list.first}' : '';
        _eligible = res['eligible'] == true;
        _slotOpen = res['slot_open'] == true;
        _hasPending = pending is List && pending.isNotEmpty;
        _revokedHistory = revoked is List
            ? [
                for (final e in revoked)
                  if (e is Map) Map<String, dynamic>.from(e),
              ]
            : const [];
      });
    } catch (_) {}
  }

  /// Dialog daftar negara dengan pencarian. Mengembalikan nama negara atau null.
  Future<String?> _showCountryPicker(BuildContext context, S s) {
    final countries = getNegaraKeys()..sort();
    return showDialog<String>(
      context: context,
      builder: (_) => CountryPickerDialog(s: s, countries: countries),
    );
  }

  /// Pilih negara (satu-satunya negara di profil).
  ///
  /// Admin memakai RPC admin (tanpa cooldown). User biasa: popup PERSETUJUAN
  /// dulu supaya sadar bahwa pindah negara mencabut jabatan moderator & lock
  /// 7 hari; lalu `set_my_country`.
  Future<void> _pickHomeCountry(
    BuildContext context,
    S s, {
    bool isAdmin = false,
  }) async {
    final picked = await _showCountryPicker(context, s);
    if (picked == null || !context.mounted) return;

    final uid = ref.read(authProvider).uid ?? '';
    if (uid.isEmpty) return;

    if (isAdmin) {
      final res = await ref
          .read(chatProvider.notifier)
          .adminSetCountry(uid, picked);
      if (!context.mounted) return;
      setState(() => _countryOverride = picked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['ok'] == true ? s.moderationCountrySaved : s.errGeneric,
          ),
        ),
      );
      return;
    }

    // Popup persetujuan: user harus SADAR sebelum pindah negara.
    final from = _effectiveCountry;
    final lockUntil =
        moderationDate(DateTime.now().add(const Duration(days: 7))
            .toIso8601String()) ??
        '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.public_rounded, color: AppTheme.danger, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(s.moderationChangeCountryTitle)),
          ],
        ),
        content: Text(
          countryChangeConfirmBody(
            from: from,
            to: picked,
            moderating: _moderatingCountry,
            lockUntil: lockUntil,
            s: s,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.moderationChangeCountryConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final res = await ref
        .read(chatProvider.notifier)
        .setMyCountry(picked);
    if (!context.mounted) return;

    if (res['ok'] == true) {
      setState(() {
        _countryOverride = picked;
        // Jabatan moderator dicabut bila server melaporkannya.
        final revoked = res['revoked_moderator_for'];
        if (revoked is List && revoked.isNotEmpty) {
          _moderatingCountry = '';
          _canOpenConsole = ref.read(authProvider.notifier).isRealAdmin;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(countryChangedMessage(res, s))),
      );
      unawaited(_loadModerationRole());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(countryCooldownMessage(res, s))),
      );
    }
  }
}
