import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../core/admin_err.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils.dart';

/// Bottom sheet detail satu entry arsip terhapus: profil + riwayat device
/// + aksi hapus user anon (pending).
class DeletedDetailSheet extends StatefulWidget {
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> locations;
  final S s;
  const DeletedDetailSheet({
    super.key,
    required this.entry,
    required this.devices,
    this.locations = const [],
    required this.s,
  });

  @override
  State<DeletedDetailSheet> createState() => _DeletedDetailSheetState();
}

class _DeletedDetailSheetState extends State<DeletedDetailSheet> {
  bool _deleting = false;

  Map<String, dynamic> get entry => widget.entry;
  List<Map<String, dynamic>> get devices => widget.devices;
  List<Map<String, dynamic>> get locations => widget.locations;
  S get s => widget.s;

  bool get _isPending => entry['pending'] == true;

  /// Hapus user anon (pending) — membebaskan nickname. Konfirmasi dulu.
  /// Blokir aksi tulis saat offline (gagal separuh jalan + membingungkan).
  bool _guardOffline(S s) => guardOfflineCtx(
    context,
    s.adminNeedsConnection,
    (m) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m))),
  );

  Future<void> _deleteAnon() async {
    if (_guardOffline(s)) return;
    final uid = '${entry['user_id'] ?? ''}';
    if (uid.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.adminDeletedDeleteTitle),
        content: Text(s.adminDeletedDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final res = await context.read<AdminProvider>().deleteAnonUser(uid);
    if (!mounted) return;
    setState(() => _deleting = false);

    final err = '${res['error'] ?? ''}';
    final msg = res['ok'] == true
        ? s.adminDeletedDeleteDone
        : err == 'REGISTERED'
        ? s.adminDeletedDeleteRegistered
        : err == 'DUMMY'
        ? s.adminDeletedDeleteDummy
        : s.adminDeletedDeleteFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: res['ok'] == true ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (res['ok'] == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final nick = '${entry['nickname'] ?? '?'}';
    final uid = '${entry['user_id'] ?? ''}';
    final email = '${entry['email'] ?? ''}';
    final registered = entry['is_registered'] == true;
    final reason = '${entry['reason'] ?? ''}';
    final claimedBy = '${entry['claimed_by'] ?? ''}';
    final claimedNick = '${entry['claimed_nick'] ?? ''}';
    final brand = '${entry['brand'] ?? ''}';
    final model = '${entry['model'] ?? ''}';
    final ip = '${entry['ip_address'] ?? ''}';
    final lastSeen = entry['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';
    final deletedAt = entry['deleted_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['deleted_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';

    final reasonLabel = switch (reason) {
      'stale_cleanup' => s.adminDeletedStale,
      'nickname_claim' => s.adminDeletedClaim,
      'admin_delete' => s.adminDeletedAdmin,
      'dummy_delete' => s.adminDeletedDummy,
      _ => reason,
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (registered ? AppTheme.primary : AppTheme.accent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                        style: AppText.bodyStrong.copyWith(
                          color: registered ? AppTheme.primary : AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nick,
                          style: AppText.title.copyWith(
                            decoration: _isPending
                                ? null
                                : TextDecoration.lineThrough,
                            decorationColor: AppTheme.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            if (_isPending) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  s.adminDeletedPending,
                                  style: AppText.micro.copyWith(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                reasonLabel,
                                style: AppText.caption.copyWith(
                                  color: _isPending
                                      ? Colors.orange
                                      : AppTheme.danger,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.adminDeviceCopyId,
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.adminDeviceCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_isPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                    ),
                    onPressed: _deleting ? null : _deleteAnon,
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_remove_rounded, size: 18),
                    label: Text(s.adminDeletedDeleteAction),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _kv(s.adminDeletedUid, uid),
                  if (email.isNotEmpty) _kv(s.adminDeviceEmail, email),
                  _kv(s.adminDeviceRegistered,
                      registered ? s.adminDeviceRegistered : s.adminDeviceAnon),
                  _kv(s.adminDeletedReason, reasonLabel),
                  _kv(s.adminDeletedAt, deletedAt),
                  _kv(s.adminDeviceLastSeen, lastSeen),
                  if (brand.isNotEmpty || model.isNotEmpty)
                    _kv(s.adminDeviceModel,
                        [brand, model].where((e) => e.isNotEmpty).join(' ')),
                  if (ip.isNotEmpty) _kv(s.adminDeviceIp, ip),
                  if (reason == 'nickname_claim') ...[
                    if (claimedBy.isNotEmpty)
                      _kv(s.adminDeletedClaimedBy, claimedBy),
                    if (claimedNick.isNotEmpty)
                      _kv(s.adminDeletedNewNick, claimedNick),
                  ],
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      s.adminDeletedDeviceHistory,
                      style: AppText.label.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeletedNoDevice,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final d in devices) _deviceTile(d),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      s.adminDeletedLocationHistory,
                      style: AppText.label.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  if (locations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeletedNoLocation,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final l in locations.take(20)) _locTile(l),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(child: Text(v, style: AppText.bodySmall)),
        ],
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final brand = '${d['brand'] ?? ''}';
    final model = '${d['model'] ?? ''}';
    final os = [
      '${d['os_name'] ?? ''}',
      '${d['os_version'] ?? ''}',
    ].where((e) => e.isNotEmpty).join(' ');
    final ip = '${d['ip_address'] ?? ''}';
    final lastSeen = d['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${d['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [brand, model].where((e) => e.isNotEmpty).join(' '),
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (os.isNotEmpty)
                  Text(
                    os,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (ip.isNotEmpty)
                  Text(
                    ip,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (lastSeen.isNotEmpty)
                  Text(
                    '${s.adminDeviceLastSeen}: $lastSeen',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _locTile(Map<String, dynamic> l) {
    final lat = '${l['lat'] ?? ''}';
    final lon = '${l['lon'] ?? ''}';
    final source = '${l['source'] ?? ''}';
    final at = l['at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${l['at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final isGps = source == 'gps';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.place_outlined,
            size: 14,
            color: isGps ? Colors.green : AppTheme.accent,
          ),
          const SizedBox(width: 6),
          Text(
            '$lat, $lon',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const Spacer(),
          if (source.isNotEmpty)
            Text(
              source,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          if (at.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              at,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
