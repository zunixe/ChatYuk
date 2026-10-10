import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import 'nearby/widgets/nearby_card.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../core/perf/perf_probe.dart';
import '../core/nav_guard.dart';

import 'private_chat_screen.dart';
import '../providers/riverpod/theme_provider.dart';
import '../providers/riverpod/location_provider.dart';

/// Cache bytes avatar hasil decode base64 — decode cukup sekali per avatar
/// (bukan setiap rebuild kartu), kapasitas dibatasi supaya tidak bocor.

/// Fitur "Orang Sekitar": cari user online/idle dalam radius tertentu
/// berdasarkan lokasi (GPS bila diizinkan, else perkiraan IP), tampilkan
/// jarak tiap user, dan bisa langsung chat.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  LocationService get _loc => ProviderScope.containerOf(context, listen: false).read(locationProvider).location;
  /// Radius maksimum yang boleh dipilih user (km) — dibatasi 50.
  static const double _maxRadiusKm = 50;
  /// Radius default saat belum ada pilihan tersimpan (km).
  static const double _defaultRadiusKm = 25;
  static const String _prefKeyRadius = 'nearby_radius_km';
  double _radiusKm = _defaultRadiusKm;
  bool _loading = true;
  bool _shareOn = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  // Paginasi.
  static const int _pageSize = 50;
  final ScrollController _scrollCtrl = ScrollController();
  bool _hasMore = true;
  bool _loadingMore = false;
  // Cegah 2 query tumpang-tindih (refresh awal + refresh GPS latar) yang
  // memicu RPC dobel & radar berkedip. Refresh terakhir menang.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await _loc.nearbyUsers(
        _radiusKm,
        limit: _pageSize,
        offset: _users.length,
      );
      if (!mounted) return;
      setState(() {
        _users = [..._users, ...rows];
        _hasMore = rows.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _init() async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    _shareOn = auth.profile?.shareLocation ?? false;
    // Muat radius tersimpan (per akun-milik device). Nilai lama dari versi
    // yang mengizinkan sampai 500km ikut di-clamp ke [_maxRadiusKm] supaya
    // tetap dalam batas baru.
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefKeyRadius);
      if (saved != null && mounted) {
        setState(() => _radiusKm = saved.clamp(1.0, _maxRadiusKm).toDouble());
      }
    } catch (_) {}
    // Anti-lag buka layar: JANGAN tunggu GPS chain (bisa belasan detik).
    // Pakai lastKnown (instan) kalau ada → langsung query. GPS akurat &
    // fallback IP jalan di BELAKANG, lalu refresh sekali bila sumber berubah.
    final lastKnown = await _loc.lastKnownPosition();
    if (!mounted) return;
    if (lastKnown != null) {
      // Radar + hasil tampil cepat dari posisi terakhir.
      unawaited(_refresh());
      // Refresh lokasi di latar; refresh ulang HANYA bila dapat posisi baru
      // (hindari RPC sia-sia saat lokasi tak berubah / gagal).
      unawaited(_loc.updateMyLocation().then((src) {
        if (!mounted || src == null) return;
        if (src == 'gps') _autoEnableShare();
        _refresh();
      }));
    } else {
      // Belum ada posisi tersimpan → tandai loading (radar) lalu resolve
      // lokasi sekali; kalau gagal, layar menampilkan empty/error, bukan
      // spinner tanpa ujung.
      unawaited(_refresh());
      final src = await _loc.updateMyLocation();
      if (!mounted) return;
      if (src == 'gps') await _autoEnableShare();
      if (mounted) await _refresh();
    }
  }

  /// Auto-enable share lokasi SEKALI — HANYA jika user mengizinkan GPS
  /// (sumber 'gps'). Kalau cuma fallback IP, jangan auto-enable.
  Future<void> _autoEnableShare() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('nearby_auto_share') ?? false) return;
    await prefs.setBool('nearby_auto_share', true);
    if (!_shareOn) {
      await _loc.setShareLocation(true);
      _shareOn = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final started = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _loc.nearbyUsers(_radiusKm, limit: _pageSize);
      // Radar minimal 350ms — cukup terasa "mencari" tanpa delay buatan
      // panjang. (Dulu 600ms = tambahan latensi murni tiap buka/geser.)
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 350)) {
        await Future.delayed(const Duration(milliseconds: 350) - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _hasMore = list.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 350)) {
        await Future.delayed(const Duration(milliseconds: 350) - elapsed);
      }
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      // Koin habis untuk Orang Sekitar (berbayar harian) → dialog topup.
      if (msg.contains('yukcoin tidak cukup') || msg.contains('not enough')) {
        setState(() => _loading = false);
        ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).showOutOfPointsDialog(
              context,
              ProviderScope.containerOf(context, listen: false).read(localeProvider).s.isId,
            );
        return;
      }
      setState(() {
        _loading = false;
        _error = msg.contains('share required')
            ? 'share_required'
            : (msg.contains('no location') ? 'no_location' : 'generic');
      });
    } finally {
      _refreshing = false;
    }
  }

  /// Simpan pilihan radius supaya tetap terpakai saat layar dibuka lagi.
  Future<void> _saveRadius(double v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyRadius, v);
    } catch (_) {}
  }

  Future<void> _toggleShare(bool v) async {
    setState(() => _shareOn = v);
    await _loc.setShareLocation(v);
    if (v) {
      // Minta izin lokasi presisi saat mengaktifkan (opsional bagi user).
      final ok = await _loc.requestPermission();
      if (!ok) {
        // User menolak/tidak pernah izinkan → tawarkan lagi via dialog.
        await _promptEnableGps();
      }
      await _loc.updateMyLocation();
    }
    await _refresh();
  }

  /// Dialog tawaran ulang akses GPS: bawa user ke Pengaturan bila dialog
  /// native Android sudah tidak muncul lagi (permission permanently denied).
  Future<void> _promptEnableGps() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          s.locSharePromptTitle,
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          s.locSharePromptBody,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.locOpenSettings),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _loc.openSettings();
    // Setelah balik dari Settings, simpan lokasi (GPS kalau diizinkan).
    await _loc.updateMyLocation();
    await _refresh();
  }

  Future<void> _startChat(Map<String, dynamic> u) async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier);
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final myUid = auth.uid;
    final otherUid = '${u['uid']}';
    if (myUid == null || otherUid == myUid) return;
    try {
      final active = await chat.isUserActive(otherUid);
      if (!mounted) return;
      if (!active) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        return;
      }
      final chatId = await chat.startPrivateChat(
        myUid: myUid,
        otherUid: otherUid,
        myName: auth.profile?.nickname ?? 'Anon',
        otherName: '${u['nickname'] ?? ''}',
        myGender: auth.profile?.gender ?? '',
        otherGender: '${u['gender'] ?? ''}',
        myCountry: auth.profile?.country ?? '',
        otherCountry: '${u['country'] ?? ''}',
        myAge: auth.profile?.age ?? 0,
        otherAge: (u['age'] as num?)?.toInt() ?? 0,
      );
      if (!mounted) return;
      final navKey = navKeyChat(chatId);
      if (!tryClaimNav(navKey)) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: chatId,
            otherName: '${u['nickname'] ?? ''}',
            otherUid: otherUid,
            otherGender: '${u['gender'] ?? ''}',
            otherCountry: '${u['country'] ?? ''}',
            otherCity: '${u['city'] ?? ''}',
            otherAge: (u['age'] as num?)?.toInt() ?? 0,
            otherRegistered: u['is_registered'] == true,
          ),
        ),
      ).then((_) => releaseNav(navKey));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Nearby');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        title: Text(s.nearbyTitle),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: AppText.title.copyWith(color: Colors.white),
      ),
      body: Column(
        children: [
          // Toggle bagikan lokasi.
          Container(
            color: AppTheme.bgCard,
            child: SwitchListTile(
              value: _shareOn,
              onChanged: _toggleShare,
              title: Text(s.nearbyShareToggle, style: AppText.bodyStrong),
              subtitle: Text(
                s.nearbyShareDesc,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              activeColor: AppTheme.primary,
            ),
          ),
          // Slider radius di-delegasikan ke widget ber-state SENDIRI supaya
          // geser slider tidak me-rebuild SELURUH layar + daftar kartu (dulu
          // setState di sini = list ikut rebuild tiap frame drag → patah-patah).
          _RadiusSlider(
            initial: _radiusKm,
            maxRadius: _maxRadiusKm,
            onChanged: (v) => _radiusKm = v,
            onChangeEnd: (v) {
              _radiusKm = v;
              _saveRadius(v);
              _refresh();
            },
          ),
          Expanded(child: _buildBody(s)),
        ],
      ),
    );
  }

  Widget _buildBody(dynamic s) {
    if (_loading) {
      return _RadarLoading(caption: s.nearbySearching);
    }
    // Catatan: TIDAK lagi memblokir saat `_shareOn == false`. Keputusan produk
    // (migrasi 20260928100000): Orang Sekitar menampilkan semua user yang
    // PUNYA koordinat lat/lon (online/idle) tanpa wajib menekan "bagikan
    // lokasi". Yang wajib hanya viewer punya lokasi sendiri (GPS) — kalau
    // tidak, server mengembalikan 'no_location' (ditangani di bawah).
    if (_error == 'share_required') {
      // Fallback lama: server versi lama masih menolak bila belum share.
      return _emptyState(
        Icons.location_off,
        s.nearbyNeedShare,
        null,
        s,
        hint: s.nearbyNeedShareDesc,
      );
    }
    if (_error == 'no_location') {
      return _emptyState(
        Icons.my_location,
        s.nearbyNoLocation,
        s.nearbyEnableLoc,
        s,
        onAction: () async {
          await _loc.requestPermission();
          await _loc.updateMyLocation();
          await _refresh();
        },
      );
    }
    if (_error != null) {
      return _emptyState(
        Icons.error_outline,
        s.errGeneric,
        s.nearbyRetry,
        s,
        onAction: _refresh,
      );
    }
    if (_users.isEmpty) {
      return _emptyState(
        Icons.group_off,
        s.nearbyEmpty,
        s.nearbyRetry,
        s,
        onAction: _refresh,
        hint: s.nearbyEmptyHint,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(
          10,
          8,
          10,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _users.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return RepaintBoundary(
            child: NearbyCard(
              data: _users[i],
              onTap: () => _startChat(_users[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String? actionLabel,
    dynamic s, {
    VoidCallback? onAction,
    String? hint,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 56,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          if (hint != null) ...[
            SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }
}

/// Slider radius dengan state SENDIRI — geser hanya rebuild widget ini,
/// bukan seluruh layar + daftar (dulu setState di parent = list rebuild tiap
/// frame → patah-patah). [onChanged] = nilai live; [onChangeEnd] = trigger query.
class _RadiusSlider extends ConsumerStatefulWidget {
  final double initial;
  /// Batas atas radius (km) — dikirim parent supaya konsisten dengan clamp
  /// nilai tersimpan.
  final double maxRadius;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _RadiusSlider({
    required this.initial,
    required this.maxRadius,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  ConsumerState<_RadiusSlider> createState() => _RadiusSliderState();
}

class _RadiusSliderState extends ConsumerState<_RadiusSlider> {
  late double _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Icon(
                Icons.social_distance,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                '${s.nearbyRadius}: ${_v.round()} km',
                style: AppText.bodyStrong,
              ),
            ],
          ),
        ),
        Slider(
          value: _v,
          min: 1,
          // Batas maksimal 50 km (kebijakan produk). Slider lama sampai
          // 500km; nilai tersimpan yang lebih besar sudah di-clamp parent.
          max: widget.maxRadius,
          divisions: (widget.maxRadius - 1).round(),
          activeColor: AppTheme.primary,
          label: '${_v.round()} km',
          onChanged: (v) {
            setState(() => _v = v);
            widget.onChanged(v);
          },
          onChangeEnd: widget.onChangeEnd,
        ),
      ],
    );
  }
}

class _RadarLoading extends StatefulWidget {
  final String caption;
  const _RadarLoading({required this.caption});

  @override
  State<_RadarLoading> createState() => _RadarLoadingState();
}

class _RadarLoadingState extends State<_RadarLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => CustomPaint(
                painter: _RadarPainter(angle: _ctrl.value * 2 * math.pi),
              ),
            ),
          ),
          SizedBox(height: 18),
          Text(
            widget.caption,
            style: AppText.body.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double angle;
  _RadarPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Lingkaran konsentris + garis silang.
    for (final f in [0.35, 0.65, 1.0]) {
      ring.color = AppTheme.primary.withValues(alpha: 0.16);
      canvas.drawCircle(center, radius * f, ring);
    }
    ring.color = AppTheme.primary.withValues(alpha: 0.10);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      ring,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      ring,
    );

    // Sapuan radar (gradient menyala di belakang garis putar).
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: angle - 0.9,
        endAngle: angle,
        colors: [
          AppTheme.primary.withValues(alpha: 0.0),
          AppTheme.primary.withValues(alpha: 0.55),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweep);

    // Garis sapuan yang berputar.
    final sweepLine = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.85)
      ..strokeWidth = 2;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      sweepLine,
    );

    // Titik pusat.
    canvas.drawCircle(center, 5, Paint()..color = AppTheme.primary);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => oldDelegate.angle != angle;
}

