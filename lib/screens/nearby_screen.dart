import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import 'nearby/widgets/nearby_card.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';

import 'private_chat_screen.dart';
import '../providers/theme_provider.dart';

/// Cache bytes avatar hasil decode base64 — decode cukup sekali per avatar
/// (bukan setiap rebuild kartu), kapasitas dibatasi supaya tidak bocor.

/// Fitur "Orang Sekitar": cari user online/idle dalam radius tertentu
/// berdasarkan lokasi (GPS bila diizinkan, else perkiraan IP), tampilkan
/// jarak tiap user, dan bisa langsung chat.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  LocationService get _loc => context.read<LocationProvider>().location;
  double _radiusKm = 10;
  bool _loading = true;
  bool _shareOn = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    _shareOn = auth.profile?.shareLocation ?? false;
    // Pakai lastKnown dulu (instan) supaya radar tidak blank — GPS akurat
    // jalan di belakang dan menyegarkan lokasi begitu selesai.
    final lastKnown = await _loc.lastKnownPosition();
    if (lastKnown != null) {
      // lastKnown sudah cukup buat query awal; background tetap refresh.
      unawaited(_loc.updateMyLocation().then((src) {
        if (src == 'gps' && mounted) {
          _autoEnableShare();
        }
      }));
    } else {
      final src = await _loc.updateMyLocation();
      if (src == 'gps') await _autoEnableShare();
    }
    await _refresh();
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
    final started = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _loc.nearbyUsers(_radiusKm);
      // Radar minimal 600ms (dulu 2,2s) — cukup terasa "mencari" tanpa
      // delay buatan panjang yang membuat fitur terkesan lambat.
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 600)) {
        await Future.delayed(const Duration(milliseconds: 600) - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 600)) {
        await Future.delayed(const Duration(milliseconds: 600) - elapsed);
      }
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _loading = false;
        _error = msg.contains('share required')
            ? 'share_required'
            : (msg.contains('no location') ? 'no_location' : 'generic');
      });
    }
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
    final s = context.read<LocaleProvider>().s;
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
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final s = context.read<LocaleProvider>().s;
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
      );
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
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
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
          // Slider( radius.
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
                  '${s.nearbyRadius}: ${_radiusKm.round()} km',
                  style: AppText.bodyStrong,
                ),
              ],
            ),
          ),
          Slider(
            value: _radiusKm,
            min: 1,
            max: 200,
            divisions: 199,
            activeColor: AppTheme.primary,
            label: '${_radiusKm.round()} km',
            onChanged: (v) => setState(() => _radiusKm = v),
            onChangeEnd: (_) => _refresh(),
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
    if (!_shareOn) {
      return _emptyState(Icons.location_off, s.nearbyNeedShare, null, s);
    }
    // Server menolak karena share_location=false (server = sumber kebenaran;
    // mis. switch lokal sempat ON padahal update gagal). Arahkan user
    // mengaktifkan berbagi — simetris: tak berbagi = tak boleh melihat.
    if (_error == 'share_required') {
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
        padding: EdgeInsets.fromLTRB(
          10,
          8,
          10,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        itemCount: _users.length,
        itemBuilder: (_, i) =>
            NearbyCard(data: _users[i], onTap: () => _startChat(_users[i])),
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

