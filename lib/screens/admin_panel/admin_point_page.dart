import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import '../../config/strings_admin.dart';
import '../../providers/riverpod/admin_provider.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../providers/riverpod/points_provider.dart';
import '../../utils.dart';
import '../../widgets/admin_error_view.dart';
import 'widgets/point_tab_cards.dart';
import 'widgets/stats_status.dart';

/// Menu "YukCoin" panel admin — statistik koin + pengaturan nominal poin.
class AdminPointPage extends ConsumerStatefulWidget {
  const AdminPointPage({super.key});
  @override
  ConsumerState<AdminPointPage> createState() => _AdminPointPageState();
}

class _AdminPointPageState extends ConsumerState<AdminPointPage> {
  final _bonusCtrl = TextEditingController(text: '100');

  // Pengaturan nominal poin (diambil dari server, diedit admin).
  final Map<String, TextEditingController> _pointCtrls = {};
  final _shareUrlCtrl = TextEditingController();
  bool _pointSettingsLoaded = false;
  // Sisa plafon promo bonus bulan ini (Rp) — read-only dari server.
  int? _promoBudgetLeft;
  bool _savingPointSettings = false;
  // Toggle boolean (Switch) pengaturan YukCoin.
  final Map<String, bool> _pointFlags = {};

  // Urutan field pengaturan YukCoin (key = kolom app_settings live).
  // Semua nilai bertipe int (bool/url ditangani terpisah).
  // Label bilingual via `s.adminPointFieldLabel(key)` di strings_admin.dart.
  // Field mati DIHAPUS (fiturnya gratis/no-op di server):
  // filter_gender_cost, nearby_cost, cost_chat_text, room_join_paid,
  // cost_undo_message, cost_edit_message, cost_extra_photo_slot,
  // cost_ghost_mode_daily.
  static const List<String> _pointFields = [
    // ── Call berbayar (per menit) ──
    'call_audio_cost_per_min',
    'call_video_cost_per_min',
    'call_cut_pct',
    // ── Biaya chat (teks gratis — hanya lampiran berbayar) ──
    'cost_chat_image',
    'cost_view_once',
    // ── Paywall foto profil female (reaktif 2026-11-08): 4 gratis, sisanya
    //  kunci permanen per foto — hanya koin berbayar.
    'photo_unlock_perm',
    'photo_unlock_owner_pct',
    // ── Room berbayar (join gratis — hanya buat/perpanjang) ──
    'room_create_paid',
    'room_create_pw_paid',
    'room_extend_paid',
    'bonus_price_multiplier',
    'promo_budget_idr_monthly',
    // ── Gift & subscribe ──
    'gift_cut_pct',
    'subscribe_cut_pct',
    'subscription_duration_days',
    // ── Welcome bonus user baru (anti-farming per install/IP) ──
    'welcome_anon_coins',
    'welcome_register_coins',
    'welcome_max_claims_per_ip_day',
    // ── Withdraw (tarik saldo ke DANA) ──
    'withdraw_rate_idr',
    'withdraw_min_coins',
    'withdraw_fee_pct',
    'withdraw_fee_min_idr',
    'withdraw_max_per_day',
    'withdraw_min_interval_hours',
    'withdraw_min_account_age_hours',
    'female_free_call_min_per_day',
    // ── Anti-fraud ──
    'coin_tx_max_per_hour',
  ];

  // Field boolean (Switch) — ditangani terpisah dari field int.
  // (reengage_enabled sengaja TIDAK di sini — bukan bagian halaman Poin.)
  static const List<String> _pointBoolFields = ['yukcoin_v2_enabled'];

  @override
  void initState() {
    super.initState();
    _loadPointSettings();
  }

  @override
  void dispose() {
    _bonusCtrl.dispose();
    _shareUrlCtrl.dispose();
    for (final c in _pointCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _loadPointSettings() async {
    try {
      final data = await ref.read(adminProvider).getPointSettings();
      if (!mounted) return;
      for (final f in _pointFields) {
        _pointCtrls[f] = TextEditingController(text: '${data[f] ?? ''}');
      }
      for (final key in _pointBoolFields) {
        _pointFlags[key] = data[key] == true;
      }
      _shareUrlCtrl.text = '${data['share_url'] ?? ''}';
      _promoBudgetLeft = (data['promo_budget_left_idr'] as num?)?.floor();
      setState(() => _pointSettingsLoaded = true);
    } catch (e) {
      dlog('[ADMIN] loadPointSettings error: $e');
    }
  }

  Future<void> _savePointSettings() async {
    setState(() => _savingPointSettings = true);
    final s = ref.read(localeProvider).s;
    try {
      final payload = <String, dynamic>{'share_url': _shareUrlCtrl.text.trim()};
      for (final e in _pointCtrls.entries) {
        final v = int.tryParse(e.value.text.trim());
        if (v != null) payload[e.key] = v;
      }
      for (final e in _pointFlags.entries) {
        payload[e.key] = e.value;
      }
      final admin = ref.read(adminProvider);
      await admin.updatePointSettings(payload);
      // Plafon bisa berubah → muat ulang sisa plafon.
      final fresh = await admin.getPointSettings();
      if (!mounted) return;
      setState(
        () => _promoBudgetLeft = (fresh['promo_budget_left_idr'] as num?)
            ?.floor(),
      );
      // Sinkron ulang status YukCoin v2 ke provider poin supaya perubahan
      // toggle (mis. membuka jalur topup) langsung terlihat tanpa restart.
      final points = ref.read(pointsProvider.notifier);
      unawaited(points.refreshYukcoinV2());
      unawaited(points.refreshMeteredPricing());
      _toast(s.adminPointSettingsSaved);
    } catch (e) {
      _toast(s.adminSaveFailed('$e'));
    } finally {
      if (mounted) setState(() => _savingPointSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(adminProvider);
    final s = ref.watch(localeProvider).s;
    final stats = admin.stats;
    final noData = stats == null || stats.isEmpty;
    if (admin.error != null && noData) {
      return AdminErrorView(
        s: s,
        error: admin.error!,
        onRetry: () => admin.fetchStats(),
      );
    }
    if (admin.loading && noData) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        await admin.fetchStats(); // cache server 5 mnt — cukup
        markAdminStatsUpdated();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          if (admin.error != null) ...[
            AdminStaleBanner(s: s),
            const SizedBox(height: 8),
          ],
          AdminLastUpdatedHeader(s: s),
          const SizedBox(height: 8),
          PointStatsCard(stats: stats, s: s),
          const SizedBox(height: 12),
          PointsSystemCard(admin: admin, s: s),
          const SizedBox(height: 12),
          FeaturePublishCard(s: s, onToast: _toast),
          const SizedBox(height: 12),
          PointSettingsCard(
            s: s,
            loaded: _pointSettingsLoaded,
            shareCtrl: _shareUrlCtrl,
            fields: _pointFields,
            notes: {
              if (_promoBudgetLeft != null)
                'promo_budget_idr_monthly': s.adminPromoBudgetLeft(
                  _promoBudgetLeft!,
                ),
            },
            ctrls: _pointCtrls,
            flags: _pointFlags,
            onFlagChanged: (k, v) => setState(() => _pointFlags[k] = v),
            saving: _savingPointSettings,
            onSave: _savePointSettings,
          ),
          const SizedBox(height: 12),
          TopEarnersCard(stats: stats, s: s),
          const SizedBox(height: 12),
          MassBonusCard(
            s: s,
            bonusCtrl: _bonusCtrl,
            admin: admin,
            onToast: _toast,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
