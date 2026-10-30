import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/call/call_permissions.dart';
import '../core/nav_guard.dart';
import '../models/random_match.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/call_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../services/random_match_service.dart';
import '../utils.dart';
import '../widgets/call_permission_dialog.dart';
import '../widgets/chat_route.dart';
import '../widgets/gender_avatar.dart';
import '../widgets/profile_style.dart';
import 'call_screen.dart';
import 'user_info_screen.dart';

/// Riwayat Random Video Call — daftar orang yang pernah tersambung.
///
/// Aksi kanan mengikuti status lawan: **video** bila sedang online (telepon
/// lagi), **chat** bila offline (lanjut ngobrol lewat pesan).
class RandomCallHistoryScreen extends ConsumerStatefulWidget {
  const RandomCallHistoryScreen({super.key});

  @override
  ConsumerState<RandomCallHistoryScreen> createState() =>
      _RandomCallHistoryScreenState();
}

class _RandomCallHistoryScreenState
    extends ConsumerState<RandomCallHistoryScreen> {
  static const int _pageSize = 30;

  final List<RandomCallEntry> _items = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  bool _hasMore = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 240) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await RandomMatchService.instance.history(limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(rows);
      _loading = false;
      _hasMore = rows.length == _pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _busy) return;
    _busy = true;
    final rows = await RandomMatchService.instance.history(
      limit: _pageSize,
      offset: _items.length,
    );
    if (!mounted) return;
    setState(() {
      _items.addAll(rows);
      _hasMore = rows.length == _pageSize;
      _busy = false;
    });
  }

  Future<void> _openChat(RandomCallEntry e) async {
    final auth = ref.read(authProvider.notifier);
    final me = auth.uid;
    if (me == null) return;
    final navKey = navKeyChat(
      ref.read(chatProvider.notifier).privateChatId(me, e.partnerId),
    );
    if (!tryClaimNav(navKey)) return;
    try {
      final chatId = await ref
          .read(chatProvider.notifier)
          .startPrivateChat(
            myUid: me,
            otherUid: e.partnerId,
            myName: auth.profile?.nickname ?? '',
            otherName: e.partnerName,
            myGender: auth.profile?.gender ?? '',
          );
      if (!mounted) return;
      await Navigator.push(
        context,
        chatRoute(
          chatId: chatId,
          otherName: e.partnerName,
          otherUid: e.partnerId,
          routeName: privateChatRoute(chatId),
        ),
      );
    } catch (err) {
      dlog('[RandomHistory] open chat error: $err');
    } finally {
      releaseNav(navKey);
    }
  }

  /// Telepon lagi (video) — alur ringing biasa, sama seperti riwayat call.
  Future<void> _callAgain(RandomCallEntry e) async {
    final s = ref.read(localeProvider).s;
    final auth = ref.read(authProvider.notifier);
    final profile = auth.profile;
    final call = ref.read(callProvider.notifier);
    if (call.inCall) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgCallInProgress)));
      return;
    }
    final perm = await ensureCallPermissions(video: true);
    if (!mounted) return;
    if (perm != CallPermissionResult.granted) {
      showCallPermissionDialog(
        context,
        video: true,
        permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
      );
      return;
    }
    final me = auth.uid;
    if (me == null) return;
    try {
      final chatId = await ref
          .read(chatProvider.notifier)
          .startPrivateChat(
            myUid: me,
            otherUid: e.partnerId,
            myName: profile?.nickname ?? '',
            otherName: e.partnerName,
            myGender: profile?.gender ?? '',
          );
      if (!mounted) return;
      final session = await call.startSession(
        callId: await call.startCall(e.partnerId, 'video'),
        remoteUid: e.partnerId,
        remoteName: e.partnerName,
        callType: 'video',
        isCaller: true,
        mode: CallMode.fullscreen,
        myName: profile?.nickname ?? '',
        myGender: profile?.gender ?? 'other',
        notifBody: s.callNotifActiveVideo,
        notifChannel: s.callNotifActiveAudio,
        notifDesc: s.callNotifActiveAudio,
        chatId: chatId,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          settings: const RouteSettings(name: kCallScreenRoute),
          builder: (_) => CallScreen(
            callId: session.callId,
            remoteUid: e.partnerId,
            remoteName: e.partnerName,
            callType: 'video',
            isCaller: true,
            chatId: chatId,
            session: session,
          ),
        ),
      );
    } catch (err) {
      dlog('[RandomHistory] call again error: $err');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgCallError)));
      }
    }
  }

  void _openProfile(RandomCallEntry e) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: e.partnerId, fallbackName: e.partnerName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      appBar: AppBar(title: Text(s.randomHistoryTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? _Empty(s: s)
          : ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                if (i == _items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Center(
                      child: Text(
                        _hasMore ? '' : s.randomHistoryEnd,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }
                final e = _items[i];
                return _HistoryTile(
                  entry: e,
                  s: s,
                  onTap: () => _openProfile(e),
                  onAction: () => e.online ? _callAgain(e) : _openChat(e),
                  onLongPress: () => showPSheet(context, [
                    PSheetAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: s.randomCallChat,
                      onTap: () => _openChat(e),
                    ),
                    PSheetAction(
                      icon: Icons.videocam_outlined,
                      label: s.randomCallNext,
                      onTap: () => _callAgain(e),
                    ),
                    PSheetAction(
                      icon: Icons.person_outline_rounded,
                      label: s.btnViewProfile,
                      onTap: () => _openProfile(e),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final RandomCallEntry entry;
  final S s;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final VoidCallback onLongPress;

  const _HistoryTile({
    required this.entry,
    required this.s,
    required this.onTap,
    required this.onAction,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  GenderAvatar(
                    uid: entry.partnerId,
                    name: entry.partnerName,
                    gender: entry.partnerGender,
                    size: 48,
                  ),
                  if (entry.online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bgCard, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.partnerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.isMissed
                          ? s.randomHistoryMissed
                          : formatMmSs(entry.durationSec),
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.randomHistoryTime(entry.startedAt),
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: AppTheme.primary.withValues(alpha: 0.16),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          entry.online
                              ? Icons.videocam_rounded
                              : Icons.chat_bubble_rounded,
                          size: 18,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final S s;

  const _Empty({required this.s});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 40,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 10),
          Text(s.randomHistoryEmpty, style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            s.randomIdleHint,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
