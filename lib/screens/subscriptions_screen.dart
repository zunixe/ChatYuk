import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/social_service.dart';
import '../widgets/profile_avatar.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final SocialService _service = SocialService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.mySubscriptions();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _unsubscribe(String creatorUid) async {
    final s = context.read<LocaleProvider>().s;
    await _service.unsubscribeCreator(creatorUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.btnUnsubscribe)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.subscriptionsTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 48, color: AppTheme.textSecondary),
                        SizedBox(height: 12),
                        Text(s.subscriptionsEmpty, style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary)),
                        SizedBox(height: 6),
                        Text(s.subscriptionsEmptyHint, textAlign: TextAlign.center, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      final name = '${e['nickname'] ?? 'Anon'}';
                      final uid = '${e['uid'] ?? ''}';
                      final price = (e['price'] as num?)?.toInt() ?? 0;
                      final registered = e['is_registered'] == true;
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(child: Text(name, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis)),
                                      if (registered) ...[
                                        SizedBox(width: 4),
                                        Icon(Icons.verified, size: 14, color: Color(0xFF4A90E2)),
                                      ],
                                    ],
                                  ),
                                  Text(s.subscribePrice(price),
                                      style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _unsubscribe(uid),
                              child: Text(s.btnUnsubscribe, style: const TextStyle(color: AppTheme.danger)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
