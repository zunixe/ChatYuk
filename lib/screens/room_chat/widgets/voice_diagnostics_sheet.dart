import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../services/room_voice_service.dart';

/// Sheet diagnostik voice room — dipakai untuk debug koneksi speaker.
///
/// Mengambil `session.diagnostics()` (timeout 8s), lalu menampilkan ringkasan
/// sesi + status tiap peer. Semua data masuk sebagai parameter; tidak
/// menyentuh state layar pemanggil.
Future<void> showVoiceDiagnosticsSheet(
  BuildContext context, {
  required RoomVoiceSession session,
  required Map<String, String> names,
  required String? myUid,
  required S s,
}) async {
  Map<String, dynamic>? diag;
  try {
    diag = await session.diagnostics().timeout(const Duration(seconds: 8));
  } catch (_) {
    diag = null;
  }
  if (!context.mounted) return;
  final me = myUid;
  final List<Widget> rows = [];
  if (diag == null) {
    rows.add(Text(s.storyViewersLoadFail, style: AppText.bodySmall));
  } else {
    rows.add(
      Text(
        'sess=${diag['sess']} joined=${diag['joined']} '
        'stage=${diag['onStage']} muted=${diag['muted']} '
        'pairing=${diag['pairing']} mic=${diag['mic']}',
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
    );
    final peers = Map<String, dynamic>.from(
      (diag['peers'] as Map?) ?? const {},
    );
    if (peers.isEmpty) {
      rows.add(
        Text(
          s.roomVoiceNoSpeakers,
          style: AppText.bodySmall.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }
    peers.forEach((key, v) {
      final m = Map<String, dynamic>.from(v as Map? ?? const {});
      final uid = key.startsWith('dn_') ? key.substring(3) : key;
      final name = uid == me ? 'Kamu' : (names[uid] ?? uid);
      final short = name.length > 10 ? '${name.substring(0, 10)}…' : name;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$short [${m['dir'] ?? '?'}] ${m['conn'] ?? '?'}'
            '/${m['ice'] ?? '?'} ${m['pair'] ?? 'no-pair'}'
            ' in=${m['in'] ?? '-'} out=${m['out'] ?? '-'}',
            style: AppText.bodySmall.copyWith(
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      );
    });
    final speakers = (diag['speakers'] as List?) ?? const [];
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'stage(${speakers.length}): ${speakers.join(', ')}',
          style: AppText.caption.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(s.roomVoiceDiagTitle, style: AppText.bodyStrong),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.roomVoiceDiagHint,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...rows,
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(s.btnClose),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
