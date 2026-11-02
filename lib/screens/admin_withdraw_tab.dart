import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/strings.dart';
import '../../config/strings_admin.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../utils.dart';

/// Model ringkas satu pengajuan withdraw (dari `admin_withdraw_list`).
class _Req {
  final String id;
  final String userId;
  final String nickname;
  final String? email;
  final int coins;
  final int rate;
  final int grossIdr;
  final int feeIdr;
  final int netIdr;
  final String status;
  final String danaNumber;
  final String danaName;
  final String? adminNote;
  final DateTime createdAt;

  const _Req({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.email,
    required this.coins,
    required this.rate,
    required this.grossIdr,
    required this.feeIdr,
    required this.netIdr,
    required this.status,
    required this.danaNumber,
    required this.danaName,
    required this.adminNote,
    required this.createdAt,
  });

  factory _Req.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    return _Req(
      id: j['id']?.toString() ?? '',
      userId: j['user_id']?.toString() ?? '',
      nickname: j['nickname'] ?? '-',
      email: j['email'],
      coins: i(j['coin_amount']),
      rate: i(j['rate']),
      grossIdr: i(j['gross_idr']),
      feeIdr: i(j['fee_idr']),
      netIdr: i(j['payout_idr']),
      status: j['status'] ?? 'pending',
      danaNumber: j['pay_account'] ?? '',
      danaName: j['pay_holder'] ?? '',
      adminNote: j['admin_note'],
      createdAt:
          DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isPending => status == 'pending';
}

/// Admin: tab Withdraw — daftar pengajuan, approve/reject manual.
/// Kartu ringkasan pengajuan MENUNGGU — total Rupiah yang harus dicairkan.
class _SummaryCard extends StatelessWidget {
  final S s;
  final int count;
  final int coins;
  final int net;
  final int fee;
  final NumberFormat rupiah;

  const _SummaryCard({
    required this.s,
    required this.count,
    required this.coins,
    required this.net,
    required this.fee,
    required this.rupiah,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE67E22), Color(0xFFD35400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined,
                  color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(
                s.adminWithdrawSummary,
                style: AppText.caption.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count ${s.adminWithdrawSummaryCount}',
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rupiah.format(net),
            style: AppText.display.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _pill('$coins 🪙', s.adminWithdrawSummaryCoins),
              const SizedBox(width: 8),
              _pill(rupiah.format(fee), s.adminWithdrawSummaryFee),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppText.micro.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppText.bodyStrong.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminWithdrawTab extends ConsumerStatefulWidget {
  const AdminWithdrawTab({super.key});

  @override
  ConsumerState<AdminWithdrawTab> createState() => _AdminWithdrawTabState();
}

class _AdminWithdrawTabState extends ConsumerState<AdminWithdrawTab> {
  static const _filters = ['pending', 'paid', 'rejected', 'all'];

  final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _noteCtrl = TextEditingController();

  String _filter = 'pending';
  List<_Req> _items = [];
  bool _loading = true;
  String? _error;
  String? _processingId;
  // Ringkasan pengajuan MENUNGGU (semua filter) — total yang harus dicairkan.
  int _pendingCount = 0;
  int _pendingCoins = 0;
  int _pendingNet = 0;
  int _pendingFee = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Daftar sesuai filter yang dipilih.
      final res = await Supabase.instance.client.rpc(
        'admin_withdraw_list',
        params: {'p_status': _filter, 'p_limit': 100},
      );
      final list = ((res['requests'] as List?) ?? const [])
          .map((e) => _Req.fromJson((e as Map).cast<String, dynamic>()))
          .toList();

      // Ringkasan SELALU dari filter 'pending' (total yang harus dicairkan),
      // terlepas dari filter yang sedang ditampilkan.
      var pCount = 0;
      var pCoins = 0;
      var pNet = 0;
      var pFee = 0;
      if (_filter == 'pending') {
        for (final r in list) {
          pCount++;
          pCoins += r.coins;
          pNet += r.netIdr;
          pFee += r.feeIdr;
        }
      } else {
        final pend = await Supabase.instance.client.rpc(
          'admin_withdraw_list',
          params: {'p_status': 'pending', 'p_limit': 500},
        );
        for (final e in ((pend['requests'] as List?) ?? const [])) {
          final r = _Req.fromJson((e as Map).cast<String, dynamic>());
          pCount++;
          pCoins += r.coins;
          pNet += r.netIdr;
          pFee += r.feeIdr;
        }
      }

      if (!mounted) return;
      setState(() {
        _items = list;
        _pendingCount = pCount;
        _pendingCoins = pCoins;
        _pendingNet = pNet;
        _pendingFee = pFee;
        _loading = false;
      });
    } catch (e) {
      dlog('[ADMIN-WD] load error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _process(_Req req, bool approve) async {
    final s = ref.read(localeProvider).s;
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          approve ? s.adminWithdrawApprove : s.adminWithdrawReject,
          style: AppText.title.copyWith(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${req.nickname} · ${req.coins} koin → '
              '${_rupiah.format(req.netIdr)}',
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              style: AppText.body.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.adminWithdrawNote,
                hintText: s.adminWithdrawNoteHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.yukcoinCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  approve ? const Color(0xFF2ECC71) : AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, _noteCtrl.text.trim()),
            child: Text(approve ? s.adminWithdrawApprove : s.adminWithdrawReject),
          ),
        ],
      ),
    );
    if (note == null) return;
    _noteCtrl.clear();

    setState(() => _processingId = req.id);
    try {
      // Respons WAJIB dibaca: server mengembalikan {ok:false, error:...}
      // sebagai JSON (bukan exception) untuk ALREADY_PROCESSED/NOT_FOUND.
      // Dulu respons dibuang → UI melaporkan "berhasil" padahal gagal.
      final res = await Supabase.instance.client.rpc(
        'admin_withdraw_process',
        params: {
          'p_request_id': req.id,
          'p_approve': approve,
          'p_note': note.isEmpty ? null : note,
        },
      );
      if (!mounted) return;
      final map = res is Map ? Map<String, dynamic>.from(res) : const {};
      final ok = map['ok'] == true;
      if (!ok) {
        final code = map['error']?.toString() ?? 'UNKNOWN';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.adminWithdrawFail}: $code'),
            backgroundColor: AppTheme.danger,
          ),
        );
        await _load();
        return;
      }
      // Reject yang berhasil → tampilkan jumlah koin yang dikembalikan.
      final refunded = (map['refunded'] as num?)?.toInt() ?? 0;
      final msg = approve
          ? s.adminWithdrawApproveOk
          : (refunded > 0
              ? s.adminWithdrawRejectRefund(refunded)
              : s.adminWithdrawRejectOk);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              approve ? const Color(0xFF2ECC71) : AppTheme.danger,
        ),
      );
      await _load();
    } catch (e) {
      dlog('[ADMIN-WD] process error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${s.adminWithdrawFail}: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;

    return Column(
      children: [
        // Ringkasan total yang harus dicairkan
        if (!_loading && _error == null && _pendingCount > 0)
          _SummaryCard(
            s: s,
            count: _pendingCount,
            coins: _pendingCoins,
            net: _pendingNet,
            fee: _pendingFee,
            rupiah: _rupiah,
          ),
        // Filter status
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filterLabel(f, s)),
                    selected: _filter == f,
                    onSelected: (_) {
                      if (_filter == f) return;
                      setState(() => _filter = f);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(s)),
      ],
    );
  }

  String _filterLabel(String f, S s) => switch (f) {
        'paid' => s.adminWithdrawFilterPaid,
        'rejected' => s.adminWithdrawFilterRejected,
        'all' => s.adminWithdrawFilterAll,
        _ => s.adminWithdrawFilterPending,
      };

  Widget _body(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.orange, size: 34),
              const SizedBox(height: 8),
              Text(
                s.adminWithdrawLoadFail,
                style: AppText.bodySmall
                    .copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(s.btnRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 34, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              s.adminWithdrawEmpty,
              style: AppText.bodySmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _card(_items[i], s),
      ),
    );
  }

  Widget _card(_Req r, S s) {
    final (color, label) = switch (r.status) {
      'paid' => (const Color(0xFF2ECC71), s.adminWithdrawFilterPaid),
      'rejected' => (AppTheme.danger, s.adminWithdrawFilterRejected),
      _ => (Colors.orange, s.adminWithdrawFilterPending),
    };
    final busy = _processingId == r.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Text(
                  r.nickname.isNotEmpty ? r.nickname[0].toUpperCase() : '?',
                  style: AppText.caption.copyWith(color: AppTheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.nickname,
                      style: AppText.bodyStrong
                          .copyWith(color: AppTheme.textPrimary),
                    ),
                    if (r.email != null && r.email!.isNotEmpty)
                      Text(
                        r.email!,
                        style: AppText.micro
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Nominal
          Row(
            children: [
              _num('${r.coins} 🪙', s.adminWithdrawCoins),
              const SizedBox(width: 14),
              _num(_rupiah.format(r.grossIdr), s.adminWithdrawGross),
              const SizedBox(width: 14),
              _num('- ${_rupiah.format(r.feeIdr)}', s.adminWithdrawFee,
                  color: AppTheme.danger),
              const SizedBox(width: 14),
              _num(_rupiah.format(r.netIdr), s.adminWithdrawNet,
                  color: const Color(0xFF2ECC71), strong: true),
            ],
          ),
          const SizedBox(height: 8),
          // Tujuan DANA
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 14, color: Color(0xFF2196F3)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${s.adminWithdrawTo}: ${r.danaNumber} · ${r.danaName}',
                  style: AppText.caption
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ),
              Text(
                _date(r.createdAt),
                style: AppText.micro
                    .copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          if (r.adminNote != null && r.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${s.adminWithdrawNote}: ${r.adminNote}',
              style: AppText.caption.copyWith(color: color),
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _process(r, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2ECC71),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 17),
                    label: Text(s.adminWithdrawApprove),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _process(r, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: BorderSide(color: AppTheme.danger),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.close, size: 17),
                    label: Text(s.adminWithdrawReject),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _num(String value, String label,
      {Color? color, bool strong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.micro.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: (strong ? AppText.bodyStrong : AppText.bodySmall)
              .copyWith(color: color ?? AppTheme.textPrimary),
        ),
      ],
    );
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
