import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_gate.dart';
import '../../../config/supabase_config.dart';
import '../../../utils.dart';
import 'section_card.dart';

/// Sesi HP harus akun admin asli (bukan sesi dummy hasil swap "masuk dummy")
/// — kalau tidak, semua RPC admin melempar 'Unauthorized' (P0001).
bool _isAdminSession() =>
    AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

/// Parse jam aktif dari RPC (List num) — aman untuk format basi.
List<int> parseAiHours(dynamic v) {
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
String aiHoursSummary(List<int> hours) {
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

/// Dialog info jadwal AI satu dummy (status kini + ringkasan jam).
void showScheduleInfoDialog(
  BuildContext context,
  Map<String, dynamic> item,
  S s,
) {
  final nickname = item['nickname'] as String? ?? '';
  final status = item['status'] as String? ?? 'offline';
  final hours = parseAiHours(item['ai_active_hours']);
  final summary = aiHoursSummary(hours);
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

/// Buka sheet Mode AI; [onSaved] dipanggil bila user menyimpan.
Future<void> showDummyAiSheet(
  BuildContext context,
  Map<String, dynamic> item, {
  Future<void> Function()? onSaved,
}) async {
  final saved = await showModalBottomSheet<bool>(
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
        child: DummyAiSheet(item: item),
      ),
    ),
  );
  if (saved == true) await onSaved?.call();
}

/// Sheet Mode AI dummy: switch aktif + persona opsional (kepribadian,
/// gaya bicara, prompt tambahan). Nama/umur/kota/hobi otomatis dari
/// profil dummy — tidak diisi manual.
class DummyAiSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  const DummyAiSheet({super.key, required this.item});

  @override
  State<DummyAiSheet> createState() => _DummyAiSheetState();
}

class _DummyAiSheetState extends State<DummyAiSheet> {
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
    _hours = parseAiHours(widget.item['ai_active_hours']);
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
            AiSectionCard(
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
            AiSectionCard(
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
            AiSectionCard(
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
                  AiSubBlock(
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
                  AiSubBlock(
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
                  AiSubBlock(
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
                  AiSubBlock(
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
                              : '${aiHoursSummary(_hours)} WIB',
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
                  : '${s.dummyAiSaved} (${aiHoursSummary(hours)} WIB)',
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

}
