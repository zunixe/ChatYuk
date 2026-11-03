import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/strings.dart';
import '../config/strings_admin_kyc.dart';
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';

/// Model satu pengajuan KYC (dari `admin_kyc_list`).
class _KycReq {
  final String id;
  final String userId;
  final String status;
  final String fullName;
  final String idType;
  final String idNumber;
  final Map<String, dynamic> checks;
  final Map<String, dynamic> serverChecks;
  final String? birthDate;
  final String? rejectReason;
  final String nickname;
  final String? email;
  final DateTime createdAt;

  const _KycReq({
    required this.id,
    required this.userId,
    required this.status,
    required this.fullName,
    required this.idType,
    required this.idNumber,
    required this.checks,
    required this.serverChecks,
    required this.birthDate,
    required this.rejectReason,
    required this.nickname,
    required this.email,
    required this.createdAt,
  });

  factory _KycReq.fromJson(Map<String, dynamic> j) => _KycReq(
        id: j['id']?.toString() ?? '',
        userId: j['user_id']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        fullName: j['full_name']?.toString() ?? '-',
        idType: j['id_type']?.toString() ?? 'ktp',
        idNumber: j['id_number']?.toString() ?? '-',
        checks: (j['checks'] as Map?)?.cast<String, dynamic>() ?? const {},
        serverChecks:
            (j['server_checks'] as Map?)?.cast<String, dynamic>() ?? const {},
        birthDate: j['birth_date']?.toString(),
        rejectReason: j['reject_reason']?.toString(),
        nickname: j['nickname']?.toString() ?? '-',
        email: j['email']?.toString(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ??
                DateTime.now(),
      );
}

/// Foto KTP + selfie satu pengajuan (sudah didecode SEKALI).
class _KycPhotos {
  final Uint8List? id;
  final Uint8List? selfie;
  const _KycPhotos(this.id, this.selfie);
}

/// Tab admin KYC — review pengajuan verifikasi identitas (syarat withdraw).
/// Daftar (`admin_kyc_list`) TANPA foto; foto diambil per pengajuan lewat
/// `admin_kyc_photos` dan di-cache (dulu semua foto + riwayat sekaligus dan
/// didecode ulang tiap rebuild). Chip "cek otomatis" = hasil OCR/liveness
/// klien + validasi NIK server, membantu admin memutuskan.
class AdminKycTab extends ConsumerStatefulWidget {
  const AdminKycTab({super.key});

  @override
  ConsumerState<AdminKycTab> createState() => _AdminKycTabState();
}

class _AdminKycTabState extends ConsumerState<AdminKycTab> {
  String _filter = 'pending';
  bool _loading = true;
  String? _error;
  List<_KycReq> _items = const [];
  final Map<String, Future<_KycPhotos>> _photos = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_kyc_list',
        params: {'p_status': _filter},
      );
      if (!mounted) return;
      final list = (res as List?)
              ?.map((e) => _KycReq.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [];
      setState(() {
        _items = list;
        _loading = false;
        _photos.clear();
      });
    } catch (e) {
      dlog('[ADMIN-KYC] load error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(_KycReq r, {required bool approve}) async {
    final s = ref.read(localeProvider).s;
    String? reason;
    if (!approve) {
      reason = await _askReason(s);
      if (reason == null) return; // batal
      if (reason.trim().isEmpty) {
        _snack(s.adminKycRejectNeedReason, error: true);
        return;
      }
    }
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_kyc_review',
        params: {
          'p_request_id': r.id,
          'p_approve': approve,
          if (reason != null) 'p_reason': reason.trim(),
        },
      );
      if (!mounted) return;
      if (res is Map && res['ok'] == false) {
        _snack(s.adminKycAlreadyProcessed, error: true);
      } else {
        _snack(approve ? s.adminKycApprovedSnack : s.adminKycRejectedSnack);
      }
      _load();
    } catch (e) {
      dlog('[ADMIN-KYC] review error: $e');
      if (mounted) _snack(e.toString(), error: true);
    }
  }

  Future<String?> _askReason(S s) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.adminKycRejectTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(hintText: s.adminKycRejectHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.btnClose),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(s.adminKycReject),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? AppTheme.danger : const Color(0xFF2ECC71),
      ),
    );
  }

  /// Data URL `data:image/jpeg;base64,…` → bytes untuk Image.memory.
  static Uint8List? _photoBytes(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      final comma = dataUrl.indexOf(',');
      return base64Decode(comma < 0 ? dataUrl : dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<_KycPhotos> _photosFor(String id) => _photos.putIfAbsent(id, () async {
        try {
          final res = await Supabase.instance.client.rpc(
            'admin_kyc_photos',
            params: {'p_request_id': id},
          );
          final j = (res as Map).cast<String, dynamic>();
          return _KycPhotos(
            _photoBytes(j['id_photo'] as String?),
            _photoBytes(j['selfie_photo'] as String?),
          );
        } catch (e) {
          dlog('[ADMIN-KYC] photos error: $e');
          _photos.remove(id);
          return const _KycPhotos(null, null);
        }
      });

  void _viewPhoto(String title, Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: InteractiveViewer(
            maxScale: 5,
            // Viewer full-screen — pengecualian cacheWidth (perlu detail
            // penuh untuk membaca dokumen); di-evict saat route ditutup.
            child: Center(child: Image.memory(bytes)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(child: Text(s.adminKycTitle, style: AppText.titleEmphasis)),
              IconButton(
                tooltip: s.btnRefresh,
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              _filterChip(s.adminKycPending, 'pending'),
              _filterChip(s.adminKycApproved, 'approved'),
              _filterChip(s.adminKycRejected, 'rejected'),
              _filterChip(s.adminKycAll, 'all'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView(s, _error!)
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            s.adminKycEmpty,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _buildCard(s, _items[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final sel = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) {
        setState(() => _filter = value);
        _load();
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.25),
    );
  }

  Widget _errorView(S s, String err) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 36),
            const SizedBox(height: 10),
            Text(err, style: AppText.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(s.btnRetry)),
          ],
        ),
      );

  Widget _buildCard(S s, _KycReq r) {
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');
    final pending = r.status == 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.bgCard,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: user + status + tanggal.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.fullName, style: AppText.bodyStrong),
                      Text(
                        '${r.nickname}${r.email != null ? ' · ${r.email}' : ''}',
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(r.status, s),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${r.idType.toUpperCase()} · ${r.idNumber}'
              '${r.birthDate != null ? ' · ${r.birthDate}' : ''}'
              ' · ${dateFmt.format(r.createdAt.toLocal())}',
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            _checksView(s, r),
            const SizedBox(height: 10),
            // Dua foto berdampingan — tap untuk viewer full-screen.
            FutureBuilder<_KycPhotos>(
              future: _photosFor(r.id),
              builder: (_, snap) {
                final p = snap.data;
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _photoThumb(
                          s, p?.id, s.adminKycDocPhoto, snap.hasData),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _photoThumb(
                          s, p?.selfie, s.adminKycSelfiePhoto, snap.hasData),
                    ),
                  ],
                );
              },
            ),
            if (!pending && (r.rejectReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${s.wdReviewNote}: ${r.rejectReason}',
                style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _review(r, approve: false),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(s.adminKycReject),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.danger,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _review(r, approve: true),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(s.adminKycApprove),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status, S s) {
    final (label, color) = switch (status) {
      'approved' => (s.adminKycApproved, const Color(0xFF2ECC71)),
      'rejected' => (s.adminKycRejected, AppTheme.danger),
      _ => (s.adminKycPending, Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: AppText.caption.copyWith(color: color)),
    );
  }

  /// Chip ✓/✗ hasil cek otomatis + nilai yang terbaca dari KTP.
  Widget _checksView(S s, _KycReq r) {
    final c = r.checks;
    final sc = r.serverChecks;
    final ocr = (c['ocr'] as Map?)?.cast<String, dynamic>() ?? const {};
    final q = (c['doc_quality'] as Map?)?.cast<String, dynamic>();
    final nameScore = (c['name_score'] as num?)?.toDouble();
    final items = <(String, bool?)>[
      (s.adminKycChkNik, sc['nik_valid'] as bool? ?? c['nik_valid'] as bool?),
      (s.adminKycChkBirth,
          sc['birth_match_nik'] as bool? ?? c['birth_match_nik'] as bool?),
      (s.adminKycChkOcr, c['ocr_ktp'] as bool?),
      (s.adminKycChkNikOcr, c['nik_match_ocr'] as bool?),
      (s.adminKycChkName, nameScore == null ? null : nameScore >= 0.8),
      (s.adminKycChkGender, sc['gender_match_profile'] as bool?),
      (s.adminKycChkLive, c['live'] as bool?),
      (s.adminKycChkQuality,
          q == null ? null : ((q['sharpness'] as num?) ?? 0) >= 60),
    ];
    final read = [
      if (ocr['nik'] != null) 'NIK ${ocr['nik']}',
      if (ocr['name'] != null) '${ocr['name']}',
      if (ocr['birth_date'] != null) '${ocr['birth_date']}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final (label, ok) in items) _checkChip(label, ok)],
        ),
        if (read.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            s.adminKycOcrRead(read),
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _checkChip(String label, bool? ok) {
    final color = ok == null
        ? AppTheme.textSecondary
        : ok
            ? const Color(0xFF2ECC71)
            : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok == null
                ? Icons.remove
                : ok
                    ? Icons.check
                    : Icons.close,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label, style: AppText.label.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _photoThumb(S s, Uint8List? bytes, String title, bool loaded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: bytes == null ? null : () => _viewPhoto(title, bytes),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: !loaded
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : bytes == null
                    ? Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.textSecondary),
                      )
                    : Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 400),
          ),
        ),
      ],
    );
  }
}
