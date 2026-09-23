import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/update_provider.dart';

/// Tampilkan popup update. Guard: hanya satu dialog pada satu waktu.
bool _showing = false;

/// Reset guard (khusus test — antar-test dialog bisa tertinggal terbuka).
@visibleForTesting
void debugResetUpdateDialogGuard() => _showing = false;

/// Dialog popup update aplikasi — menampilkan versi baru + catatan rilis,
/// dengan progres unduhan (Play Core flexible) dan tombol aksi.
///
/// - Update biasa: bisa ditutup ("Nanti" → snooze 24 jam).
/// - Update wajib (versi < min_version): tanpa tombol Nanti, back diblok.
void showUpdateDialog(BuildContext context, UpdateProvider provider) {
  if (_showing) return;
  _showing = true;
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !provider.force,
    builder: (ctx) => _UpdateDialog(provider: provider),
  ).whenComplete(() {
    _showing = false;
    provider.notifyDialogClosed();
  });
}

class _UpdateDialog extends StatelessWidget {
  final UpdateProvider provider;
  const _UpdateDialog({required this.provider});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return ListenableBuilder(
      listenable: provider,
      builder: (ctx, _) {
        final phase = provider.phase;
        // Fase idle = dialog sudah selesai (mis. setelah snooze) → tutup.
        if (phase == UpdatePhase.idle) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = Navigator.of(ctx, rootNavigator: true);
            if (nav.canPop()) nav.pop();
          });
          return const SizedBox.shrink();
        }

        final force = provider.force;
        final title = force ? s.updateRequiredTitle : s.updateTitle;
        final body = force
            ? s.updateRequiredMsg
            : (provider.latestVersion.isEmpty
                  ? s.updateAvailableMsg('')
                  : s.updateAvailableMsg(provider.latestVersion));

        return PopScope(
          canPop: !force,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(
                        Icons.system_update_rounded,
                        size: 48,
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: AppText.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (provider.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgScreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.updateNotesLabel,
                            style: AppText.label.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(provider.notes, style: AppText.bodySmall),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _actions(context, s, phase, force),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actions(
    BuildContext context,
    S s,
    UpdatePhase phase,
    bool force,
  ) {
    // Sedang mengunduh (Play flexible).
    if (phase == UpdatePhase.downloading) {
      return Column(
        children: [
          const SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(minHeight: 6),
          ),
          const SizedBox(height: 8),
          Text(
            provider.progress > 0
                ? s.updateDownloading(provider.progress)
                : s.updatePreparing,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    // Unduhan selesai → tinggal restart.
    if (phase == UpdatePhase.readyToInstall) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => provider.applyAndRestart(),
          child: Text(s.btnUpdateRestart),
        ),
      );
    }

    // Non-Play: arahkan ke listing Play di browser.
    if (!provider.fromPlay && phase != UpdatePhase.failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.updateOpenStoreMsg,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!force)
                TextButton(
                  onPressed: () => provider.snooze(),
                  child: Text(s.btnUpdateLater),
                ),
              if (!force) const SizedBox(width: 8),
              FilledButton(
                onPressed: () => provider.openStore(),
                child: Text(s.btnOpenStore),
              ),
            ],
          ),
        ],
      );
    }

    // Fase gagal / tersedia → tombol utama.
    final isFailed = phase == UpdatePhase.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFailed) ...[
          Text(
            s.updateFailed,
            style: AppText.caption.copyWith(color: AppTheme.danger),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!force) ...[
              TextButton(
                onPressed: () => provider.snooze(),
                child: Text(s.btnUpdateLater),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton(
              onPressed: () => provider.startUpdate(),
              child: Text(
                isFailed ? s.btnRetry : s.btnUpdateNow,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
