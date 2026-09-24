import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/fonts.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';

/// Pilih font global aplikasi (katalog AppFonts) — berlaku semua user
/// realtime. Default = Poppins + Roboto (perilaku lama).
class AppFontTile extends StatelessWidget {
  const AppFontTile({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    final currentKey = auth.appFontFamily;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.text_fields_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminFontTitle,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.adminFontDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.adminFontCurrent}: ${AppFonts.label(currentKey)}',
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            color: AppTheme.primary,
            tooltip: s.adminFontTitle,
            onPressed: () => _showFontSheet(context, currentKey),
          ),
        ],
      ),
    );
  }

  void _showFontSheet(BuildContext context, String currentKey) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AppFontSheet(currentKey: currentKey),
    );
  }
}

/// Bottom sheet picker font + preview live.
class AppFontSheet extends StatefulWidget {
  final String currentKey;
  const AppFontSheet({super.key, required this.currentKey});

  @override
  State<AppFontSheet> createState() => _AppFontSheetState();
}

class _AppFontSheetState extends State<AppFontSheet> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = AppFonts.resolve(widget.currentKey);
  }

  Future<void> _save() async {
    if (guardOfflineCtx(context, context.read<LocaleProvider>().s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
    final s = context.read<LocaleProvider>().s;
    setState(() => _saving = true);
    await context.read<AuthProvider>().setAppFontFamily(_selected);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(s.adminFontSaved)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.adminFontPickTitle,
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              s.adminFontDefaultNote,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Preview live mengikuti font yang dipilih.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgScreen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.adminFontPreviewHeading,
                    style: AppFonts.previewStyle(
                      _selected,
                      size: 24,
                      weight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      fallback: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.adminFontPreviewBody,
                    style: AppFonts.previewStyle(
                      _selected,
                      size: 14,
                      weight: FontWeight.w400,
                      color: AppTheme.textPrimary,
                      fallback: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Baris Light: pembanding "tipis" antar font terpilih.
                  Text(
                    s.adminFontPreviewLight,
                    style: AppFonts.previewStyle(
                      _selected,
                      size: 14,
                      weight: AppFonts.lightWeight,
                      color: AppTheme.textSecondary,
                      fallback: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v ?? _selected),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final opt in AppFonts.options)
                        RadioListTile<String>(
                          value: opt.key,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            opt.label,
                            style: AppFonts.previewStyle(
                              opt.key,
                              size: 15,
                              weight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              fallback: 'Poppins',
                            ),
                          ),
                          // Sampel cut Light per font — kalimat sama untuk
                          // semua opsi supaya bisa dibandingkan tanpa memilih
                          // satu per satu (Inter vs DM Sans vs Figtree vs
                          // Manrope vs Plus Jakarta Sans).
                          subtitle: Text(
                            s.adminFontSampleShort,
                            style: AppFonts.previewStyle(
                              opt.key,
                              size: 14,
                              weight: AppFonts.lightWeight,
                              color: AppTheme.textSecondary,
                              fallback: 'Roboto',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(s.btnSave),
            ),
          ],
        ),
      ),
    );
  }
}
