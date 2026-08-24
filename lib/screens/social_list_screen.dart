import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/social_service.dart';
import '../widgets/profile_avatar.dart';
import '../providers/theme_provider.dart';

/// Daftar sosial (followers / following / friends / subscribers).
/// `kind` menentukan tipe; `userId` menentukan user yang diambil (diri sendiri
/// bila null). Default 'followers'.
class SocialListScreen extends StatefulWidget {
  final String kind;
  final String? userId;
  final String? title;
  const SocialListScreen({
    super.key,
    required this.kind,
    this.userId,
    this.title,
  });

  @override
  State<SocialListScreen> createState() => _SocialListScreenState();
}

class _SocialListScreenState extends State<SocialListScreen> {
  final SocialService _service = SocialService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.userId ?? _service.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final items = await _service.socialList(widget.kind, uid);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final title =
        widget.title ??
        switch (widget.kind) {
          'followers' => s.socialFollowers,
          'following' => s.socialFollowing,
          'friends' => s.socialFriends,
          'subscribers' => s.socialSubscribers,
          _ => '',
        };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _items.isEmpty
          ? Center(
              child: Text(
                s.socialListEmpty,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                itemBuilder: (_, i) => _SocialTile(entry: _items[i]),
              ),
            ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _SocialTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final name = '${entry['nickname'] ?? 'Anon'}';
    final uid = '${entry['uid'] ?? ''}';
    final registered = entry['is_registered'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ProfileAvatar(uid: uid, name: name, size: 40, borderRadius: 20),
            const SizedBox(width: 10),
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
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified,
                      size: 14,
                      color: Color(0xFF4A90E2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
