import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../main.dart';
import '../providers/call_provider.dart';
import '../providers/locale_provider.dart';
import '../screens/private_chat_screen.dart';
import '../screens/call_screen.dart';
import '../services/call_service.dart';

class CallBanner extends StatefulWidget {
  const CallBanner({super.key});

  @override
  State<CallBanner> createState() => _CallBannerState();
}

class _CallBannerState extends State<CallBanner> {
  Timer? _ticker;
  String _dur = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final sess = CallProvider.instance.activeSession;
    if (sess == null || sess.connectedAt == null) {
      if (_dur.isNotEmpty) setState(() => _dur = '');
      return;
    }
    final sec = DateTime.now().difference(sess.connectedAt!).inSeconds;
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    final t = '$m:$s';
    if (t != _dur) setState(() => _dur = t);
  }

  bool _shouldShow(CallSession? sess, CallMode? mode, String? chatId, String? curChatId) {
    if (sess == null) return false;
    if (sess.phase == CallPhase.ended) return false;
    // Jika sedang di private chat yang sama (overlay sudah terlihat) → jangan tampil banner.
    if (mode == CallMode.chat && chatId != null && curChatId == chatId) {
      return false;
    }
    // Jika CallScreen fullscreen sedang di atas stack → jangan tampil (deteksi via navigator).
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      // Cek route teratas mengandung CallScreen – lewat context tidak akurat,
      // pakai flag: jika mode fullscreen dan ada route, tetap tampil banner saat di luar call.
      // Sederhana: jika mode fullscreen, banner selalu tampil kecuali ada CallScreen di stack.
      // Kita deteksi dengan melihat apakah ada Route dengan CallScreen type di navigator.
      // Fallback: jangan sembunyikan – user bisa tap banner untuk kembali.
    }
    return true;
  }

  void _onTap(CallSession sess, CallMode? mode, String? chatId) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (mode == CallMode.chat && chatId != null) {
      nav.push(MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          chatId: chatId,
          otherUid: sess.remoteUid,
          otherName: sess.remoteName,
        ),
      ));
    } else {
      nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          callId: sess.callId,
          remoteUid: sess.remoteUid,
          remoteName: sess.remoteName,
          callType: sess.callType,
          isCaller: sess.isCaller,
          session: sess,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<CallProvider>();
    final s = context.watch<LocaleProvider>().s;
    final sess = prov.activeSession;
    final mode = prov.activeMode;
    final chatId = prov.activeChatId;

    return ValueListenableBuilder<String?>(
      valueListenable: activeChatId,
      builder: (_, curChatId, __) {
        final show = _shouldShow(sess, mode, chatId, curChatId);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (c, a) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(a),
        child: c,
      ),
      child: !show || sess == null
          ? const SizedBox.shrink(key: ValueKey('hide'))
          : SafeArea(
              key: const ValueKey('show'),
              bottom: false,
              child: GestureDetector(
                onTap: () => _onTap(sess, mode, chatId),
                child: Container(
                  height: 36,
                  margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B8A43),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sess.callType == 'video' ? Icons.videocam : Icons.call,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sess.remoteName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(color: Colors.white),
                            ),
                            Text(
                              _dur.isEmpty ? s.callBannerTap : '$_dur • ${s.callBannerTap}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.micro.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s.callBannerTap,
                          style: AppText.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        );
      },
    );
  }
}
