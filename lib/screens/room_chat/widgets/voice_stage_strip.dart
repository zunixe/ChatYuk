import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../models/user_model.dart';
import '../../../providers/riverpod/room_voice_provider.dart';
import '../../../widgets/person_avatar.dart';

/// Tombol mic voice stage di AppBar room global.
/// - Belum join: mic mati (tap = masuk + langsung naik stage).
/// - Join tapi belum stage: mic (tap = naik stage).
/// - Stage + bunyi: mic hijau (tap = mute).
/// - Stage + mute: mic mati merah (tap = unmute).
/// - Tahan: keluar voice sepenuhnya.
class VoiceMicButton extends StatelessWidget {
  final RoomVoiceSession? session;
  final bool joining;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const VoiceMicButton({
    super.key,
    required this.session,
    required this.joining,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    // Pairing (uplink belum Connected) = spinner — tanda "lagi nyambung",
    // beda dari mic hijau (sudah connected). Tanpa ini user tak tahu mic-nya
    // pairing atau connect (laporan global room).
    final pairing = s?.pairing ?? false;
    Widget icon;
    if (joining || pairing) {
      icon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    } else if (s != null && !s.joined) {
      icon = const Icon(Icons.mic_off_rounded, color: Colors.white, size: 22);
    } else if (s != null && s.onStage && !s.muted) {
      icon = const Icon(Icons.mic_rounded, color: Color(0xFF2E9E5B), size: 22);
    } else if (s != null && s.onStage) {
      icon = const Icon(Icons.mic_off_rounded, color: AppTheme.danger, size: 22);
    } else {
      icon = const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22);
    }
    // Tanpa kapsul/background — ikon polos seperti tombol AppBar lain.
    return ListenableBuilder(
      listenable: s ?? ChangeNotifier(),
      builder: (_, child) => GestureDetector(
        onTap: joining ? null : onTap,
        onLongPress: (s == null || !s.joined) ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: icon,
        ),
      ),
    );
  }
}

/// Avatar speaker yang BERDENYUT saat ia bicara (pulse scale + glow hijau).
/// Controller hidup per avatar, hanya repeat selama speaking=true — diam
/// (skala 1.0) saat tidak bicara. TickerMode layar mematikan animasi tab
/// non-aktif seperti animasi lain.
class _SpeakingAvatar extends StatefulWidget {
  final bool speaking;
  final Color bg;
  final String label;
  /// Foto asli user (lazy via [PersonAvatar]) + ring warna gender.
  final String uid;
  final String gender;

  const _SpeakingAvatar({
    required this.speaking,
    required this.bg,
    required this.label,
    required this.uid,
    required this.gender,
  });

  @override
  State<_SpeakingAvatar> createState() => _SpeakingAvatarState();
}

class _SpeakingAvatarState extends State<_SpeakingAvatar>
    with SingleTickerProviderStateMixin {
  static const _pulseGreen = Color(0xFF2E9E5B);
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 1.1).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_SpeakingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speaking == oldWidget.speaking) return;
    if (widget.speaking) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      decoration: widget.speaking
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _pulseGreen, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: _pulseGreen.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      // PersonAvatar = standar yang sama persis dengan Pengguna Online
      // (foto + latar tint + ring warna gender).
      child: PersonAvatar(
        uid: widget.uid,
        name: widget.label,
        gender: widget.gender,
        size: 44,
      ),
    );
    if (!widget.speaking) return avatar;
    return ScaleTransition(scale: _scale, child: avatar);
  }
}

/// Strip speaker voice stage (global room): avatar + nama + status mic.
/// - Border hijau berdenyut saat orangnya BICARA (audio-level).
/// - Ikon gembok/mute bila dimute (sendiri/admin).
/// - Tap avatar speaker (bukan diri) → [onSpeakerTap] (layar membuka sheet
///   mute bila boleh moderasi).
class VoiceStageStrip extends StatelessWidget {
  final RoomVoiceSession session;
  final Map<String, UserModel> usersByUid;
  final String? myUid;
  final void Function(String uid) onSpeakerTap;

  const VoiceStageStrip({
    super.key,
    required this.session,
    required this.usersByUid,
    required this.myUid,
    required this.onSpeakerTap,
  });

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder di dalam (bukan watch) agar strip rebuild sendiri
    // tanpa me-rebuild seluruh layar room tiap level audio berubah.
    return ListenableBuilder(
      listenable: session,
      builder: (_, child) {
        final speakers = session.speakers.toList();
        if (speakers.isEmpty) return const SizedBox.shrink();
        return Container(
          height: 86,
          color: AppTheme.bgCard,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: speakers.length,
            itemBuilder: (_, i) {
              final uid = speakers[i];
              final user = usersByUid[uid];
              final name = uid == myUid
                  ? 'Kamu'
                  : (user?.nickname ?? 'User');
              final speaking = session.isSpeaking(uid);
              final muted = uid == myUid
                  ? (session.onStage && session.muted)
                  : session.isMuted(uid);
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  // Avatar sendiri → sheet diagnostik (debug suara).
                  // Avatar orang → sheet mute (bila boleh moderasi).
                  onTap: () => onSpeakerTap(uid),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _SpeakingAvatar(
                            speaking: speaking,
                            bg: uid == myUid
                                ? AppTheme.primary
                                : AppTheme.accent,
                            label: name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            uid: uid,
                            gender: user?.gender ?? '',
                          ),
                          if (muted)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppTheme.danger,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.mic_off_rounded,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 56,
                        child: Text(
                          speaking ? '$name •' : name,
                          style: AppText.micro.copyWith(
                            color: speaking
                                ? const Color(0xFF2E9E5B)
                                : AppTheme.textSecondary,
                            fontWeight: speaking
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
