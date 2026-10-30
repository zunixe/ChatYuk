import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/random_match.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/random_match_provider.dart';
import '../widgets/gender_avatar.dart';
import 'random_call_history_screen.dart';
import 'random_call_screen.dart';

/// Layar utama Random Video Call: radar orang sekitar + tombol Match.
///
/// Avatar di radar hanya ANIMASI user online (tidak bisa diklik) — aksi
/// sesungguhnya hanya tombol Match (masuk antrean & langsung video call
/// tanpa konfirmasi).
class RandomMatchScreen extends ConsumerStatefulWidget {
  const RandomMatchScreen({super.key});

  @override
  ConsumerState<RandomMatchScreen> createState() => _RandomMatchScreenState();
}

class _RandomMatchScreenState extends ConsumerState<RandomMatchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;
  bool _callRouteOpen = false;
  String? _lastError;

  /// Notifier ditangkap saat initState: `ref` TIDAK boleh dipakai di
  /// dispose() (Flutter melempar "Cannot use ref after the widget was
  /// disposed" → timer & antrean jadi bocor).
  late final RandomMatchNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(randomMatchProvider.notifier);
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    // Data radar + refresh berkala (20 dtk) selama layar terbuka.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifier.attach();
    });
  }

  @override
  void dispose() {
    _float.dispose();
    _notifier.detach();
    // Keluar layar = keluar antrean + tutup call (tanpa menunggu UI).
    _notifier.leaveScreen();
    super.dispose();
  }

  String _errorText(S s, String? code) {
    switch (code) {
      case 'FEATURE_DISABLED':
        return s.randomErrFeature;
      case 'ALREADY_IN_CALL':
      case 'CALL_DISABLED':
        return s.randomErrInCall;
      case 'CALL_REGISTERED_ONLY':
        return s.randomErrRegistered;
      default:
        return s.randomErrGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final st = ref.watch(randomMatchProvider);

    // Error dari provider → snackbar sekali per kode.
    if (st.errorCode != null && st.errorCode != _lastError) {
      _lastError = st.errorCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorText(s, st.errorCode))));
      });
    } else if (st.errorCode == null) {
      _lastError = null;
    }

    // Sudah tersambung → buka layar video call sekali.
    if (st.phase == RandomMatchPhase.inCall && !_callRouteOpen) {
      _callRouteOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RandomCallScreen()),
        );
        _callRouteOpen = false;
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _MapPainter())),
          _RadarAvatars(animation: _float, users: st.sample),
          if (st.isSearching)
            Center(child: _PulseRing(animation: _float)),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  s: s,
                  onHistory: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RandomCallHistoryScreen(),
                    ),
                  ),
                ),
                const Spacer(),
                _Counter(s: s, state: st),
                const SizedBox(height: 18),
                _GenderChips(
                  s: s,
                  value: st.wantGender,
                  onChanged: _notifier.setWantGender,
                ),
                const SizedBox(height: 18),
                _MatchButton(
                  s: s,
                  searching: st.isSearching,
                  onTap: () {
                    final n = _notifier;
                    if (st.isSearching) {
                      n.cancel();
                    } else {
                      n.start();
                    }
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final S s;
  final VoidCallback onHistory;

  const _TopBar({required this.s, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              s.randomTitle,
              style: AppText.title.copyWith(color: Colors.white),
            ),
          ),
          IconButton(
            tooltip: s.randomHistoryTitle,
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Avatar melayang di radar. Posisi tetap per slot, animasi naik-turun halus.
class _RadarAvatars extends StatelessWidget {
  final Animation<double> animation;
  final List<RandomRadarUser> users;

  const _RadarAvatars({required this.animation, required this.users});

  static const _slots = <Offset>[
    Offset(0.50, 0.20),
    Offset(0.22, 0.30),
    Offset(0.78, 0.31),
    Offset(0.10, 0.44),
    Offset(0.60, 0.45),
    Offset(0.86, 0.47),
  ];

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    final shown = users.take(_slots.length).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = animation.value * 2 * math.pi;
            return Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: _slots[i].dx * size.width - 36,
                    top:
                        _slots[i].dy * size.height -
                        46 +
                        math.sin(t + i * 1.1) * 7,
                    child: _RadarAvatar(user: shown[i]),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RadarAvatar extends StatelessWidget {
  final RandomRadarUser user;

  const _RadarAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GenderAvatar(
            uid: user.uid,
            name: user.nickname,
            gender: user.gender,
            size: 56,
            borderWidth: 2,
          ),
          const SizedBox(height: 4),
          Text(
            user.distanceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final S s;
  final RandomMatchState state;

  const _Counter({required this.s, required this.state});

  @override
  Widget build(BuildContext context) {
    final n = state.isSearching ? state.waiting : state.online;
    final label = state.isSearching
        ? s.randomWaitingCount(state.waiting)
        : s.randomIdleHint;
    return Column(
      children: [
        Text(
          '$n',
          style: AppText.display.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: Colors.white70),
          ),
        ),
        if (state.isSearching && state.waiting == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
            child: Text(
              s.randomEmptyPool,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

class _GenderChips extends StatelessWidget {
  final S s;
  final String value;
  final ValueChanged<String> onChanged;

  const _GenderChips({
    required this.s,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <String, String>{
      'all': s.randomGenderAll,
      'male': s.randomGenderMale,
      'female': s.randomGenderFemale,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in items.entries) ...[
          _Chip(
            label: e.value,
            selected: value == e.key,
            onTap: () => onChanged(e.key),
          ),
          if (e.key != 'female') const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: AppText.label.copyWith(
              color: selected ? const Color(0xFF0B0F14) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchButton extends StatelessWidget {
  final S s;
  final bool searching;
  final VoidCallback onTap;

  const _MatchButton({
    required this.s,
    required this.searching,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: SizedBox(
        height: 60,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: searching ? AppTheme.danger : AppTheme.quickTimeline,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          icon: Icon(
            searching ? Icons.close_rounded : Icons.bolt_rounded,
            size: 24,
          ),
          label: Text(
            searching ? s.btnRandomCancel : s.btnRandomMatch,
            style: AppText.button.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Lingkaran berdenyut saat mencari pasangan.
class _PulseRing extends StatelessWidget {
  final Animation<double> animation;

  const _PulseRing({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        return IgnorePointer(
          child: Container(
            width: 120 + v * 220,
            height: 120 + v * 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.quickTimeline.withValues(
                  alpha: (1 - v) * 0.45,
                ),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Latar "peta gelap" sederhana — garis jalan tipis, tanpa tile berbayar.
class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF11161D), Color(0xFF0B0F14)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final road = Paint()
      ..color = const Color(0xFF1C2430)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final thin = Paint()
      ..color = const Color(0xFF161D27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Deterministik (seed tetap) supaya tidak "berkedip" saat rebuild.
    final rnd = math.Random(7);
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.08 + i * 0.13);
      final path = Path()..moveTo(-20, y);
      var x = 0.0;
      while (x < size.width + 40) {
        x += size.width * (0.18 + rnd.nextDouble() * 0.16);
        path.lineTo(x, y + (rnd.nextDouble() - 0.5) * 46);
      }
      canvas.drawPath(path, i.isEven ? road : thin);
    }
    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.12 + i * 0.2);
      final path = Path()..moveTo(x, -20);
      var y = 0.0;
      while (y < size.height + 40) {
        y += size.height * (0.16 + rnd.nextDouble() * 0.18);
        path.lineTo(x + (rnd.nextDouble() - 0.5) * 40, y);
      }
      canvas.drawPath(path, thin);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}
