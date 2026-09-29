import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/call/call_history_entry.dart';
import '../core/call/call_permissions.dart';
import '../core/nav_guard.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../utils.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/call_permission_dialog.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/profile_avatar.dart';
import 'call_screen.dart';
import 'private_chat_screen.dart';

/// Halaman "Panggilan Terbaru" — riwayat call masuk/keluar ala WhatsApp,
/// dibuka dari menu titik-3 di tab Pesan.
///
/// Tap baris → buka private chat; ikon call di kanan → panggil ulang jenis
/// panggilan terakhir. Data dibaca lewat [CallProvider] (screen dilarang
/// import `services/`).
class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallHistoryEntry>? _entries;
  Map<String, String> _names = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final call = context.read<CallProvider>();
    final me = auth.uid;
    if (me == null || me.isEmpty) {
      if (mounted) {
        setState(() {
          _entries = const [];
          _loading = false;
        });
      }
      return;
    }
    try {
      final rows = await call.recentCalls();
      final list = <CallHistoryEntry>[];
      for (final r in rows) {
        final e = CallHistoryEntry.fromRow(r, me);
        if (e != null) list.add(e);
      }
      // Nama lawan bicara (batch, hindari N+1).
      final uids = list.map((e) => e.otherUid).toSet().toList();
      Map<String, String> names = const {};
      if (uids.isNotEmpty) {
        try {
          names = await call.lookupNames(uids);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _entries = list;
          _names = names;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = const [];
          _loading = false;
        });
      }
    }
  }

  String _nameFor(String uid, S s) {
    final n = _names[uid];
    return (n != null && n.isNotEmpty) ? n : s.unknownUser;
  }

  /// Buka chat dengan lawan bicara baris ini.
  Future<void> _openChat(CallHistoryEntry e) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final profile = auth.profile;
    final me = auth.uid;
    if (me == null) return;
    final otherName = _nameFor(e.otherUid, context.read<LocaleProvider>().s);
    final navKey = navKeyChat(chat.privateChatId(me, e.otherUid));
    if (!tryClaimNav(navKey)) return;
    try {
      final chatId = await chat.startPrivateChat(
        myUid: me,
        otherUid: e.otherUid,
        myName: profile?.nickname ?? '',
        otherName: otherName,
        myGender: profile?.gender ?? '',
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          settings: RouteSettings(name: privateChatRoute(chatId)),
          builder: (_) => PrivateChatScreen(
            chatId: chatId,
            otherName: otherName,
            otherUid: e.otherUid,
          ),
        ),
      );
    } catch (err) {
      debugPrint('[CALL-HISTORY] openChat gagal: $err');
    } finally {
      releaseNav(navKey);
    }
  }

  /// Panggil ulang jenis panggilan terakhir — gate anon/dummy + izin
  /// kamera/mikrofon, sama persis dengan alur panggil dari layar chat.
  Future<void> _redial(CallHistoryEntry e) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    final call = context.read<CallProvider>();
    if (call.inCall) {
      showChatSnack(context, s.msgCallInProgress);
      return;
    }
    final callType = e.isVideo ? 'video' : 'audio';
    // Gate anon & dummy: hanya boleh call bila toggle admin ON.
    final registeredCaller =
        (profile?.isRegistered ?? false) && !auth.dummySessionActive;
    if (!registeredCaller && !auth.callAnonEnabled) {
      showAnonPromptDialog(
        context,
        title: s.promptCompleteEmailCallTitle,
        message: s.promptCompleteEmailCallMsg,
        icon: Icons.call_outlined,
      );
      return;
    }
    final perm = await ensureCallPermissions(video: callType == 'video');
    if (!mounted) return;
    if (perm != CallPermissionResult.granted) {
      showCallPermissionDialog(
        context,
        video: callType == 'video',
        permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
      );
      return;
    }
    final otherName = _nameFor(e.otherUid, s);
    try {
      final chatId = await context.read<ChatProvider>().startPrivateChat(
        myUid: auth.uid!,
        otherUid: e.otherUid,
        myName: profile?.nickname ?? '',
        otherName: otherName,
        myGender: profile?.gender ?? '',
      );
      if (!mounted) return;
      final session = await call.startSession(
        callId: await call.startCall(e.otherUid, callType),
        remoteUid: e.otherUid,
        remoteName: otherName,
        callType: callType,
        isCaller: true,
        mode: callType == 'video' ? CallMode.chat : CallMode.fullscreen,
        myName: profile?.nickname ?? '',
        myGender: profile?.gender ?? 'other',
        notifBody: callType == 'video'
            ? s.callNotifActiveVideo
            : s.callNotifActiveAudio,
        notifChannel: s.callNotifActiveAudio,
        notifDesc: s.callNotifActiveAudio,
        chatId: chatId,
      );
      if (!mounted) return;
      if (callType != 'video') {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            settings: const RouteSettings(name: kCallScreenRoute),
            builder: (_) => CallScreen(
              callId: session.callId,
              remoteUid: e.otherUid,
              remoteName: otherName,
              callType: callType,
              isCaller: true,
              chatId: chatId,
              session: session,
            ),
          ),
        );
      }
      // Video: overlay muncul otomatis dari provider.activeSession.
    } catch (err) {
      debugPrint('[CALL-HISTORY] redial gagal: $err');
      showChatSnack(context, s.msgCallError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.menuRecentCalls)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_entries == null || _entries!.isEmpty)
            ? _EmptyHistory(s: s)
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _entries!.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final e = _entries![i];
                  return _CallHistoryTile(
                    entry: e,
                    name: _nameFor(e.otherUid, s),
                    onTap: () => _openChat(e),
                    onRedial: () => _redial(e),
                  );
                },
              ),
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final CallHistoryEntry entry;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onRedial;

  const _CallHistoryTile({
    required this.entry,
    required this.name,
    required this.onTap,
    required this.onRedial,
  });

  @override
  Widget build(BuildContext context) {
    final s = Provider.of<LocaleProvider>(context).s;
    final missed = entry.isMissedIncoming;
    return ListTile(
      onTap: onTap,
      leading: ProfileAvatar(uid: entry.otherUid, name: name, size: 44),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.bodyStrong.copyWith(
          color: missed ? AppTheme.danger : null,
        ),
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            entry.isOutgoing
                ? Icons.call_made_rounded
                : Icons.call_received_rounded,
            size: 14,
            color: missed ? AppTheme.danger : AppTheme.textSecondary,
          ),
          const SizedBox(width: 4),
          Icon(
            entry.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            size: 14,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _subtitle(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          entry.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          color: AppTheme.accent,
          size: 22,
        ),
        tooltip: s.callRedial,
        onPressed: onRedial,
      ),
    );
  }

  String _subtitle(S s) {
    final time = formatRelativeTime(entry.at, isId: s.isId);
    final dir = entry.isOutgoing ? s.callDirOutgoing : s.callDirIncoming;
    switch (entry.outcome) {
      case CallOutcome.missed:
        return '${s.msgCallMissed} · $time';
      case CallOutcome.declined:
        return '${s.msgCallDeclined} · $time';
      case CallOutcome.canceled:
        return '${s.msgCallEnded} · $time';
      case CallOutcome.busy:
        return '${s.msgCallBusy} · $time';
      case CallOutcome.ongoing:
        return '$dir · $time';
      case CallOutcome.completed:
        return entry.hasDuration
            ? '$dir · $time · ${formatMmSs(entry.durationSec)}'
            : '$dir · $time';
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  final S s;

  const _EmptyHistory({required this.s});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Column(
            children: [
              Icon(
                Icons.call_outlined,
                size: 40,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                s.callHistoryEmpty,
                style: AppText.bodyStrong.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  s.callHistoryEmptyHint,
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
