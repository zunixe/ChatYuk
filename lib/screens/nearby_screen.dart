import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';

import '../services/location_service.dart';
import '../utils/bounded_cache.dart';
import 'private_chat_screen.dart';
import '../providers/theme_provider.dart';

/// Cache bytes avatar hasil decode base64 — decode cukup sekali per avatar
/// (bukan setiap rebuild kartu), kapasitas dibatasi supaya tidak bocor.
final _avatarBytesCache = BoundedCache<String, Uint8List>(80);

/// Fitur "Orang Sekitar": cari user online/idle dalam radius tertentu
/// berdasarkan lokasi (GPS bila diizinkan, else perkiraan IP), tampilkan
/// jarak tiap user, dan bisa langsung chat.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final LocationService _loc = LocationService();
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
    // Pastikan lokasi terbaru sebelum query (GPS bila diizinkan, else IP).
    final src = await _loc.updateMyLocation();
    // Auto-enable share lokasi SEKALI — HANYA jika user mengizinkan GPS
    // (sumber 'gps'). Kalau cuma fallback IP, jangan auto-enable.
    // Tanpa ini hampir semua user default false → radar selalu kosong
    // padahal banyak yang online. Toggle manual tetap dihormati.
    if (src == 'gps') {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('nearby_auto_share') ?? false)) {
        await prefs.setBool('nearby_auto_share', true);
        if (!_shareOn) {
          await _loc.setShareLocation(true);
          _shareOn = true;
        }
      }
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final started = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _loc.nearbyUsers(_radiusKm);
      // Radar minimal 2,2 detik — biar terasa "mencari", bukan flash.
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 2200)) {
        await Future.delayed(const Duration(milliseconds: 2200) - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(milliseconds: 2200)) {
        await Future.delayed(const Duration(milliseconds: 2200) - elapsed);
      }
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        _loading = false;
        _error = msg.contains('no location') ? 'no_location' : 'generic';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
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
      Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(
        chatId: chatId,
        otherName: '${u['nickname'] ?? ''}',
        otherUid: otherUid,
        otherGender: '${u['gender'] ?? ''}',
        otherCountry: '${u['country'] ?? ''}',
        otherCity: '${u['city'] ?? ''}',
        otherAge: (u['age'] as num?)?.toInt() ?? 0,
        otherRegistered: u['is_registered'] == true,
      )));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
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
          decoration: BoxDecoration(
            gradient: AppTheme.headerGradient,
          ),
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
              subtitle: Text(s.nearbyShareDesc, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
              activeColor: AppTheme.primary,
            ),
          ),
          // Slider( radius.
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.social_distance, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text('${s.nearbyRadius}: ${_radiusKm.round()} km', style: AppText.bodyStrong),
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
    if (_error == 'no_location') {
      return _emptyState(Icons.my_location, s.nearbyNoLocation, s.nearbyEnableLoc, s, onAction: () async {
        await _loc.requestPermission();
        await _loc.updateMyLocation();
        await _refresh();
      });
    }
    if (_error != null) {
      return _emptyState(Icons.error_outline, s.errGeneric, s.nearbyRetry, s, onAction: _refresh);
    }
    if (_users.isEmpty) {
      return _emptyState(Icons.group_off, s.nearbyEmpty, s.nearbyRetry, s, onAction: _refresh, hint: s.nearbyEmptyHint);
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        itemCount: _users.length,
        itemBuilder: (_, i) => _NearbyCard(
          data: _users[i],
          onTap: () => _startChat(_users[i]),
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String? actionLabel, dynamic s,
      {VoidCallback? onAction, String? hint}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(title, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppTheme.textSecondary)),
          ),
          if (hint != null) ...[
            SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
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
          Text(widget.caption, style: AppText.body.copyWith(color: AppTheme.textSecondary)),
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
        Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), ring);
    canvas.drawLine(
        Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), ring);

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

class _NearbyCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _NearbyCard({required this.data, required this.onTap});

  Color _statusColor(String status) {
    if (status == 'idle') return AppTheme.idle;
    if (status == 'offline') return AppTheme.offline;
    return AppTheme.online;
  }

  String _distanceLabel(dynamic s, double km) {
    if (km < 1) return s.nearbyDistanceM((km * 1000).round());
    return s.nearbyDistanceKm(km.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final nickname = '${data['nickname'] ?? ''}';
    final gender = '${data['gender'] ?? ''}';
    final age = (data['age'] as num?)?.toInt() ?? 0;
    final city = '${data['city'] ?? ''}';
    final country = '${data['country'] ?? ''}';
    final status = '${data['status'] ?? 'online'}';
    final avatar = '${data['avatar'] ?? ''}';
    final isRegistered = data['is_registered'] == true;
    final distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0;
    final color = gender == 'male' ? AppTheme.male : gender == 'female' ? AppTheme.female : AppTheme.accent;
    final genderLabel = gender == 'male' ? s.genderMale : gender == 'female' ? s.genderFemale : s.genderOther;

    final avatarBytes = avatar.isNotEmpty
        ? _avatarBytesCache.putIfAbsent(avatar, () {
            try {
              return base64Decode(avatar);
            } catch (_) {
              return Uint8List(0);
            }
          })
        : null;
    final hasAvatar = avatarBytes?.isNotEmpty == true;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: color, width: 1.5),
                        image: hasAvatar
                            ? DecorationImage(image: MemoryImage(avatarBytes!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: hasAvatar
                          ? null
                          : Center(child: Text(
                              nickname.isNotEmpty ? nickname[0].toUpperCase() : '?',
                              style: TextStyle(color: color, fontSize: AppGlyph.avatarInitial(44), fontWeight: FontWeight.w700))),
                    ),
                    Positioned(right: 0, bottom: 0,
                      child: Container(width: 12, height: 12,
                        decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(nickname, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis)),
                        if (isRegistered) ...[
                          SizedBox(width: 4),
                          Icon(Icons.verified, size: 15, color: Color(0xFF4A90E2)),
                        ],
                      ]),
                      Text('$genderLabel $age · $city, $country',
                          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(children: [
                        const Icon(Icons.location_on, size: 12, color: AppTheme.primary),
                        const SizedBox(width: 2),
                        Text(_distanceLabel(s, distanceKm),
                            style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chat_bubble_outline, color: AppTheme.primary, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
