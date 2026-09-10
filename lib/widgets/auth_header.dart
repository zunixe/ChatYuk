import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/strings.dart';
import '../config/theme.dart';

/// Logo + tagline + subtagline — dipakai EntryScreen & RegisterScreen
/// supaya tampilan awal selalu konsisten.
class AuthHeader extends StatelessWidget {
  final S s;
  const AuthHeader({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo — animasi halus dalam lingkaran transparan.
        Center(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const AnimatedLogo(),
          ),
        ),
        const SizedBox(height: 4),

        AuthTitle(s.appTagline),
        const SizedBox(height: 1),
        Text(
          s.appSubtagline,
          textAlign: TextAlign.center,
          style: AppText.bodySmall.copyWith(
            color: AppTheme.textSecondary,
            shadows: [
              Shadow(
                blurRadius: 6,
                color: Colors.black.withValues(alpha: 0.8),
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Judul gaya tagline — gradient cerah di light mode, solid redup di dark
/// mode. Dipakai header auth & judul popup profil supaya selalu konsisten.
class AuthTitle extends StatelessWidget {
  final String text;
  const AuthTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    if (AppTheme.isDark) {
      return Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.display.copyWith(
          color: const Color(0xFFAEB9C4),
          letterSpacing: 0.5,
          shadows: [
            Shadow(
              blurRadius: 10,
              color: Colors.black.withValues(alpha: 0.7),
              offset: const Offset(0, 2),
            ),
          ],
        ),
      );
    }
    return ShaderMask(
      shaderCallback: (bounds) =>
          AppTheme.headerGradient.createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.display.copyWith(
          color: Colors.white,
          letterSpacing: 0.5,
          shadows: [
            Shadow(
              blurRadius: 10,
              color: Colors.black.withValues(alpha: 0.65),
              offset: const Offset(0, 2),
            ),
            Shadow(
              blurRadius: 20,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo app dengan animasi halus: ayun kiri-kanan, mengambang naik-turun,
/// dan denyut opacity seperti asap. Skala seragam → ikon tetap proporsional.
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({super.key});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(math.sin(t) * 8, math.sin(t * 2) * 5 - 2),
          child: Opacity(
            opacity: 0.85 + 0.15 * math.sin(t * 2 + math.pi / 2),
            child: Transform.scale(
              scale: 1.0 + 0.05 * math.sin(t),
              child: child,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset('assets/app_icon.png', width: 56, height: 56),
      ),
    );
  }
}
