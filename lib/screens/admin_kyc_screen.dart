import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/kyc_service.dart';
import '../providers/theme_provider.dart';

/// Review KYC (admin). Menampilkan permohonan + foto, setujui/tolak.
class AdminKycScreen extends StatefulWidget {
  const AdminKycScreen({super.key});
  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends State<AdminKycScreen> {
  final _rejectCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _tab = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await KycService.instance.adminList(_tab);
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
  }

  Future<void> _review(Map<String, dynamic> item, bool approve) async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(s.kycRejectTitle, style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: _rejectCtrl,
            maxLines: 2,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(labelText: s.kycRejectReason, labelStyle: TextStyle(color: AppTheme.textSecondary)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnCancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(ctx, _rejectCtrl.text.trim()),
              child: Text(s.btnReject, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    try {
      await KycService.instance.adminReview(requestId: item['id'], approve: approve, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text(approve ? s.kycApprovedToast : s.kycRejectedToast)));
      _rejectCtrl.clear();
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${s.kycSubmitFailed}: $e')));
    }
  }

  @override
  void dispose() {
    _rejectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: AppBar(
          title: Text(s.adminKycTitle),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800),
            unselectedLabelStyle: AppText.body.copyWith(fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: s.kycStatusPending),
              Tab(text: s.kycStatusApproved),
              Tab(text: s.kycStatusRejected),
              Tab(text: 'All'),
            ],
          ),
        ),
        body: TabBarView(
          children: ['pending', 'approved', 'rejected', 'all'].map((t) => _listTab(s, t)).toList(),
        ),
      ),
    );
  }

  Widget _listTab(S s, String tab) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          TextButton(onPressed: () { _tab = tab; _load(); }, child: Text(s.btnRefresh)),
        ]),
      ),
      Expanded(child: _listBody(s, tab)),
    ]);
  }

  Widget _listBody(S s, String tab) {
    if (_loading && tab == _tab) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(child: Text(s.kycNoRequests, style: TextStyle(color: AppTheme.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _itemCard(s, _items[i]),
      ),
    );
  }

  Widget _itemCard(S s, Map<String, dynamic> it) {
    final status = it['status'] ?? '';
    final name = it['full_name'] ?? '';
    final idNumber = it['id_number'] ?? '';
    final idType = it['id_type'] == 'passport' ? s.kycIdTypePassport : s.kycIdTypeKtp;
    final nickname = it['nickname'] ?? '';
    final email = it['email'] ?? '';
    final createdAt = it['created_at']?.toString().split('T').first ?? '';
    final rejectReason = it['reject_reason'];

    final color = switch (status) {
      'approved' => const Color(0xFF2E7D32),
      'rejected' => AppTheme.danger,
      _ => const Color(0xFFF9A825),
    };

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$name (${nickname.isEmpty ? '?' : nickname})',
                style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(_statusLabel(s, status), style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        SizedBox(height: 6),
        Text('$idType — $idNumber', style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        Text('$email • $createdAt', style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        if (rejectReason != null && rejectReason.toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${s.kycRejectReason}: $rejectReason',
              style: AppText.bodySmall.copyWith(color: AppTheme.danger)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _photo(s, it['id_photo'], s.kycIdPhoto)),
          const SizedBox(width: 10),
          Expanded(child: _photo(s, it['selfie_photo'], s.kycSelfie)),
        ]),
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger)),
                onPressed: () => _review(it, false),
                icon: const Icon(Icons.close, size: 16),
                label: Text(s.btnReject),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => _review(it, true),
                icon: const Icon(Icons.check, size: 16),
                label: Text(s.btnApprove, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  String _statusLabel(S s, String status) => switch (status) {
        'approved' => s.kycStatusApproved,
        'rejected' => s.kycStatusRejected,
        _ => s.kycStatusPending,
      };

  Widget _photo(S s, Object? data, String label) {
    if (data is! String || data.length < 100) {
      return Container(
        height: 140,
        decoration: BoxDecoration(color: AppTheme.bgInput, borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(label, style: AppText.caption.copyWith(color: AppTheme.textSecondary))),
      );
    }
    return Container(
      height: 140,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          Image.memory(base64Decode(data), fit: BoxFit.cover),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Center(child: Text(label, style: AppText.micro.copyWith(color: Colors.white))),
            ),
          ),
        ]),
      ),
    );
  }
}
