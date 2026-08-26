import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/points_service.dart';
import '../providers/theme_provider.dart';

class PointHistoryScreen extends StatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  State<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<PointHistoryScreen> {
  final PointsService _service = PointsService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.pointHistory(limit: 200);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[PointHistory] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.pointHistoryTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    s.pointHistoryEmpty,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 40,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, i) =>
                    const Divider(height: 1, indent: 64),
                itemBuilder: (_, i) => _HistoryTile(entry: _items[i], s: s),
              ),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final S s;
  const _HistoryTile({required this.entry, required this.s});

  @override
  Widget build(BuildContext context) {
    final amount = ((entry['amount'] as num?) ?? 0).toInt();
    final isCredit = amount > 0;
    // Ledger: field 'type' (fallback 'event' untuk kompat lama)
    final event = '${entry['type'] ?? entry['event']}';
    final bucket = '${entry['bucket'] ?? ''}';
    final ref = '${entry['ref_id'] ?? ''}';
    final metadata = (entry['metadata'] as Map?) ?? const {};
    final title = _eventLabel(event, ref, metadata, s);
    final sub = _bucketLabel(bucket, s);
    final bucketColor = _bucketColor(bucket, isCredit);

    final created = entry['created_at'];
    final time = DateTime.tryParse('$created')?.toLocal() ?? DateTime.now();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: bucketColor.withValues(alpha: 0.12),
        child: Icon(
          isCredit ? Icons.add : Icons.remove,
          color: bucketColor,
          size: 20,
        ),
      ),
      title: Text(title, style: AppText.bodyStrong),
      subtitle: Text(
        sub,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isCredit ? '+' : ''}$amount',
            style: AppText.bodyStrong.copyWith(
              color: bucketColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2),
          Text(
            DateFormat('dd MMM yyyy HH:mm').format(time),
            style: AppText.micro.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // Warna per bucket: bonus=biru, topup=hijau, earned=emas, default hijau/merah.
  Color _bucketColor(String bucket, bool isCredit) {
    switch (bucket) {
      case 'bonus':
        return Colors.blueGrey;
      case 'topup':
        return Colors.green;
      case 'earned':
        return const Color(0xFFB8860B);
      default:
        return isCredit ? Colors.green : Colors.red;
    }
  }

  String _eventLabel(String event, String ref, Map metadata, S s) {
    switch (event) {
      // Ledger spend types
      case 'spend_chat':
        final t = '${metadata['msg_type'] ?? ref}';
        if (t == 'image') return s.pointHistoryDeductImage;
        if (t == 'view_once' || t == 'view_once_expired')
          return s.pointHistoryDeductViewOnce;
        return s.pointHistoryDeductText;
      case 'deduct':
        final t = '${metadata['msg_type']}';
        if (t == 'image') return s.pointHistoryDeductImage;
        if (t == 'view_once' || t == 'view_once_expired')
          return s.pointHistoryDeductViewOnce;
        return s.pointHistoryDeductText;
      case 'daily_login':
        return s.pointHistoryDailyLogin;
      case 'new_chat':
        return s.pointHistoryNewChat;
      case 'room_read':
        return s.pointHistoryRoomRead;
      case 'one_time':
      case 'bonus':
        return _bonusLabel('${metadata['action']}', s);
      case 'weekly_quest':
        return s.pointHistoryWeeklyQuest;
      case 'coin_sent':
        return s.pointHistoryCoinSent;
      case 'coin_received':
        return s.pointHistoryCoinReceived;
      case 'spend_room':
        if (ref == 'create') return s.pointHistoryRoomCreate;
        if (ref == 'join') return s.pointHistoryRoomJoin;
        if (ref == 'extend') return s.pointHistoryRoomExtend;
        return s.pointHistoryRoomCreate;
      case 'private_room_create':
        return s.pointHistoryRoomCreate;
      case 'private_room_join':
        return s.pointHistoryRoomJoin;
      case 'private_room_income':
        return s.pointHistoryRoomIncome;
      case 'private_room_extend':
        return s.pointHistoryRoomExtend;
      case 'admin_mass_bonus':
        return s.pointHistoryAdminBonus;
      case 'admin_reset_all':
      case 'admin_adjust':
        return s.pointHistoryAdminReset;
      case 'migrate':
        return s.pointHistoryOther;
      default:
        return s.pointHistoryOther;
    }
  }

  // Label bucket coin (bonus/topup/earned) sebagai subtitle
  String _bucketLabel(String bucket, S s) {
    switch (bucket) {
      case 'bonus':
        return s.walletBucketBonus;
      case 'topup':
        return s.walletBucketTopup;
      case 'earned':
        return s.walletBucketEarned;
      default:
        return '';
    }
  }

  String _bonusLabel(String action, S s) {
    switch (action) {
      case 'registered':
        return s.pointHistoryRegister;
      case 'first_photo':
        return s.pointHistoryFirstPhoto;
      case 'rated_app':
        return s.pointHistoryRateApp;
      case 'shared_app':
        return s.pointHistoryShare;
      case 'completed_profile':
        return s.pointHistoryProfile;
      case 'online_5min':
        return s.pointHistoryOnline5;
      case 'online_30min':
        return s.pointHistoryOnline30;
      case 'online_60min':
        return s.pointHistoryOnline60;
      case 'online_120min':
        return s.pointHistoryOnline120;
      default:
        return s.pointHistoryOther;
    }
  }
}
