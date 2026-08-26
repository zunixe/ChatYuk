import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/social_provider.dart';
import '../services/social_service.dart';
import '../widgets/profile_avatar.dart';
import '../providers/theme_provider.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final SocialService _service = SocialService();
  bool _loading = true;
  List<Map<String, dynamic>> _inbox = [];
  List<Map<String, dynamic>> _outbox = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inbox = await _service.friendRequestInbox();
    final outbox = await _service.friendRequestOutbox();
    if (!mounted) return;
    setState(() {
      _inbox = inbox;
      _outbox = outbox;
      _loading = false;
    });
  }

  Future<void> _respond(Map<String, dynamic> req, bool accept) async {
    final id = (req['id'] as num?)?.toInt() ?? 0;
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.respondFriendRequest(id, accept);
      if (accept && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.friendRequestAccepted)),
        );
      }
      await _load();
      if (mounted) context.read<SocialProvider>().refreshInbox();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.friendRequestTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _inbox.isEmpty && _outbox.isEmpty
          ? Center(
              child: Text(
                s.friendRequestEmpty,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                children: [
                  if (_inbox.isNotEmpty) ...[
                    Text(
                      s.socialFollowers,
                      style: AppText.label.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 6),
                    ..._inbox.map(
                      (r) => _RequestTile(
                        entry: r,
                        pending: true,
                        onAccept: () => _respond(r, true),
                        onReject: () => _respond(r, false),
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                  if (_outbox.isNotEmpty) ...[
                    Text(
                      s.btnFriendRequested,
                      style: AppText.label.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._outbox.map(
                      (r) => _RequestTile(entry: r, pending: false),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final bool pending;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  const _RequestTile({
    required this.entry,
    required this.pending,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final name = '${entry['nickname'] ?? 'Anon'}';
    final uid = '${entry['uid'] ?? ''}';
    final registered = entry['is_registered'] == true;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ProfileAvatar(uid: uid, name: name, size: 40, borderRadius: 20),
          SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: AppText.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (registered) ...[
                  SizedBox(width: 4),
                  Icon(Icons.verified, size: 14, color: Color(0xFF4A90E2)),
                ],
              ],
            ),
          ),
          if (pending) ...[
            TextButton(
              onPressed: onReject,
              child: Text(
                s.btnCancel,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: onAccept,
              child: Text(s.btnConfirm, style: TextStyle(color: Colors.white)),
            ),
          ] else
            Text(
              s.btnFriendRequested,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}
