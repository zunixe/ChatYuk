import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/gifts.dart';
import '../../../config/theme.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/chat_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';

/// Klaster dialog koin & pemilih gift untuk chat 1:1.
///
/// Dulu ~330 baris inline di `private_chat_screen` (`_showSendCoinDialog` +
/// `_showGiftPicker`). Sekarang fungsi murni yang MENGEMBALIKAN pilihan;
/// pengiriman (RPC + poin + toast) tetap di screen. Tidak menyentuh state
/// layar → mudah dipakai ulang & diuji.

/// Dialog laporkan pengguna — BERSAMA private ↔ room.
///
/// Dulu disalin utuh di dua screen (beda hanya sumber id/nama target).
void showReportUserDialog(
  BuildContext context, {
  required String reportedId,
  required String reportedName,
  /// Bila diisi → laporan menunjuk PESAN (bukan hanya user). Server
  /// menyembunyikan pesan otomatis setelah >=3 pelapor berbeda.
  String? messageId,
}) {
  String reason = '';
  String reasonCode = 'other';
  final s = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localeProvider).s;

  // Pilihan alasan (bilingual) — kode dikirim ke server, label ke user.
  final codes = <String>[
    'porn',
    'violence',
    'spam',
    'scam',
    'other',
  ];
  String labelOf(String code) {
    switch (code) {
      case 'porn':
        return s.reportReasonPorn;
      case 'violence':
        return s.reportReasonViolence;
      case 'spam':
        return s.reportReasonSpam;
      case 'scam':
        return s.reportReasonScam;
      default:
        return s.reportReasonOther;
    }
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          '${s.btnReport} $reportedName',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in codes)
                  ChoiceChip(
                    label: Text(labelOf(code)),
                    selected: reasonCode == code,
                    onSelected: (_) => setLocal(() => reasonCode = code),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(hintText: s.reportHint),
              onChanged: (v) => reason = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () async {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              final router = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              if (messageId != null) {
                final res = await container
                    .read(chatProvider.notifier)
                    .reportRoomMessage(
                      messageId,
                      reasonCode: reasonCode,
                      note: reason,
                    );
                router.pop();
                messenger.showSnackBar(SnackBar(
                  content: Text(
                    res['auto_hidden'] == true
                        ? s.reportHiddenNow
                        : s.reportSuccess,
                  ),
                ));
                return;
              }
              final uid = container.read(authProvider.notifier).uid;
              if (uid != null) {
                await container.read(chatProvider.notifier).reportUser(
                      reporterId: uid,
                      reportedId: reportedId,
                      reason: reason,
                    );
              }
              router.pop();
              messenger.showSnackBar(SnackBar(content: Text(s.reportSuccess)));
            },
            child: Text(
              s.btnReport,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Dialog kirim koin. Return jumlah yang dipilih, atau null bila dibatalkan.
/// `canUsePaid=false` → dialog tidak dibuka (pemanggil tampilkan pesan).
Future<int?> showSendCoinDialog(
  BuildContext context, {
  required String otherName,
  required bool pointsEnabled,
  required int paidBalance,
}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _SendCoinDialog(
      otherName: otherName,
      pointsEnabled: pointsEnabled,
      paidBalance: paidBalance,
    ),
  );
}

class _SendCoinDialog extends StatefulWidget {
  const _SendCoinDialog({
    required this.otherName,
    required this.pointsEnabled,
    required this.paidBalance,
  });

  final String otherName;
  final bool pointsEnabled;
  final int paidBalance;

  @override
  State<_SendCoinDialog> createState() => _SendCoinDialogState();
}

class _SendCoinDialogState extends State<_SendCoinDialog> {
  final _amountCtrl = TextEditingController();
  int _selected = 0;
  static const _presets = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header gradient elegan
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryDark,
                    AppTheme.primary,
                    AppTheme.accent,
                  ],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '🪙',
                        style: TextStyle(fontSize: AppGlyph.lg),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.sendCoinTitle,
                    style: AppText.title.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.sendCoinTo(widget.otherName),
                    style: AppText.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Saldo kamu
                    if (widget.pointsEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFB300,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFFFFB300,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '🪙',
                              style: TextStyle(fontSize: AppGlyph.sm),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.labelYourCoins,
                                style: AppText.bodySmall.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            Text(
                              '${widget.paidBalance}',
                              style: AppText.bodyStrong.copyWith(
                                color: const Color(0xFFFFB300),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    const SizedBox(height: 14),
                    Text(
                      s.coinAmountLabel,
                      style: AppText.label.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    // Preset jumlah
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.map((p) {
                        final isSel = _selected == p;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selected = p;
                            _amountCtrl.text = '$p';
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppTheme.primary
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSel
                                    ? AppTheme.primary
                                    : Colors.white.withValues(alpha: 0.12),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '$p 🪙',
                              style: AppText.bodyStrong.copyWith(
                                color: isSel ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    // Input custom
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _selected = 0),
                      style: AppText.body.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: s.coinAmountHint,
                        hintStyle: AppText.body.copyWith(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.coinDialogHelper,
                      style: AppText.caption.copyWith(color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        s.btnCancel,
                        style: AppText.bodyStrong.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        final amount =
                            int.tryParse(_amountCtrl.text.trim()) ?? 0;
                        if (amount < 5) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(s.errCoinMin)));
                          return;
                        }
                        if (widget.pointsEnabled &&
                            amount > widget.paidBalance) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.errCoinInsufficient)),
                          );
                          return;
                        }
                        Navigator.pop(context, amount);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(s.btnSend, style: AppText.button),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet pemilih gift. Return gift terpilih, atau null bila dibatalkan.
Future<GiftItem?> showGiftPickerSheet(
  BuildContext context, {
  required bool pointsEnabled,
  required int paidBalance,
  required int bonusBalance,
  required int bonusMultiplier,
}) {
  final s = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(localeProvider).s;
  return showModalBottomSheet<GiftItem>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.giftTitle, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              s.giftPick,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            if (!pointsEnabled) ...[
              const SizedBox.shrink(),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                '${s.paidBalanceLabel}: $paidBalance',
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 200,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.8,
                ),
                itemCount: kGiftCatalog.length,
                itemBuilder: (ctx, i) {
                  final g = kGiftCatalog[i];
                  final afford =
                      g.coins <= paidBalance ||
                      (g.coins * bonusMultiplier) <= bonusBalance;
                  return InkWell(
                    onTap: afford ? () => Navigator.pop(ctx, g) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: afford
                            ? AppTheme.bgInput
                            : AppTheme.bgInput.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: afford
                              ? Colors.pinkAccent.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            g.emoji,
                            style: TextStyle(fontSize: AppGlyph.lg),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.isId ? g.nameId : g.nameEn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${g.coins} 🪙',
                            style: AppText.caption.copyWith(
                              color: afford
                                  ? const Color(0xFFB8860B)
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
