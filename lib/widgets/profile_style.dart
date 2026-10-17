import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';

/// Palet & komponen tampilan PROFIL (gaya Instagram/WA gelap) — satu tempat.
class PColors {
  /// Background & card MENGIKUTI TEMA halaman Profil sendiri
  /// (`AppTheme.bgScreen` / `bgCard`) supaya konsisten saat mode terang.
  static Color get bg => AppTheme.bgScreen;
  static Color get divider => AppTheme.divider;
  static Color get card => AppTheme.bgCard;
  static Color get cardDivider => AppTheme.divider;
  static Color get surface => AppTheme.bgCard;
  static const border = Color(0xFF2E3440);
  static const handle = Color(0xFF3A404C);
  static const text = Color(0xFFE8EAED);
  static const textStrong = Color(0xFFF2F4F7);
  static const textSoft = Color(0xFFB4BAC2);
  static const chipText = Color(0xFFC9CDD3);
  static const muted = Color(0xFF8E959F);
  static const faint = Color(0xFF6B727C);
  static const accent = Color(0xFF2F95E8);
  static const link = Color(0xFF4FB3F6);
  static const online = Color(0xFF22C46B);
  static const offline = Color(0xFF9AA0A8);
  static const danger = Color(0xFFFF6B6F);
  static const dangerSolid = Color(0xFFE5484D);
  static const scrim = Color(0x73000000);
}

/// Toast profil (snackbar ringkas ala desain).
void showProfileToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: PColors.bg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: PColors.textStrong,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 1800),
      ),
    );
}

Future<void> copyWithToast(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showProfileToast(context, message);
}

/// Tombol bulat di header: semi-gelap di atas foto, polos saat solid.
class PHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool solid;
  final double iconSize;
  final VoidCallback? onTap;

  const PHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.solid,
    this.onTap,
    this.iconSize = 21,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: solid ? Colors.transparent : const Color(0x66000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Placeholder foto (inisial) saat tidak ada foto.
class PNoPhoto extends StatelessWidget {
  final String initials;
  const PNoPhoto({super.key, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B6A96), Color(0xFF1C3550), Color(0xFF121B27)],
        ),
      ),
      alignment: const Alignment(0, -0.2),
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 96,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Baris statistik; `asCard: true` = dibungkus kartu.
class PStat {
  final int value;
  final String label;
  final VoidCallback? onTap;
  const PStat(this.value, this.label, {this.onTap});
}

class PStatsRow extends StatelessWidget {
  final List<PStat> stats;
  final bool asCard;
  const PStatsRow({super.key, required this.stats, this.asCard = false});

  String _format(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}jt';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}rb';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        for (final s in stats)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: s.onTap,
              child: SizedBox(
                height: asCard ? 64 : 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _format(s.value),
                      style: TextStyle(
                        color: PColors.textStrong,
                        fontSize: asCard ? 17 : 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.label,
                      style: const TextStyle(
                        color: PColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (!asCard) return row;
    return Container(
      decoration: BoxDecoration(
        color: PColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: row,
    );
  }
}

/// Chip minat/hashtag.
class PChip extends StatelessWidget {
  final String text;
  final double height;
  const PChip({super.key, required this.text, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PColors.surface,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: PColors.chipText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Kartu info ala WhatsApp: ikon, nilai (putih), label (abu).
class PInfoItem {
  final IconData icon;
  final String value;
  final String label;
  final Widget? trailing;
  final bool tabular;
  const PInfoItem({
    required this.icon,
    required this.value,
    required this.label,
    this.trailing,
    this.tabular = false,
  });
}

class PInfoCard extends StatelessWidget {
  final List<PInfoItem> items;
  const PInfoCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: PColors.cardDivider,
              ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(items[i].icon, size: 22, color: PColors.muted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: PColors.textStrong,
                            fontSize: 15,
                            fontFeatures: items[i].tabular
                                ? const [FontFeature.tabularFigures()]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          style: const TextStyle(
                            color: PColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (items[i].trailing != null)
                    items[i].trailing!
                  else
                    const SizedBox(width: 14),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PCopyButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const PCopyButton({super.key, required this.onTap, this.tooltip = 'Salin'});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: const Icon(Icons.copy_rounded, size: 20, color: PColors.link),
    );
  }
}

/// Empty state ringkas.
class PEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const PEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 40, color: PColors.faint),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: PColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: PColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/* ═════════════ Bottom sheet & dialog ═════════════ */

class PSheetAction {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const PSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

Future<void> showPSheet(BuildContext context, List<PSheetAction> actions) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: PColors.handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            for (final a in actions)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(sheetContext);
                  a.onTap();
                },
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        a.icon,
                        size: 22,
                        color: a.destructive ? PColors.danger : PColors.text,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        a.label,
                        style: TextStyle(
                          color: a.destructive ? PColors.danger : PColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class PDialogButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const PDialogButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Konfirmasi putus pertemanan (gaya desain profil).
Future<bool> confirmPUnfriend(
  BuildContext context, {
  required String name,
  String title = 'Putus pertemanan?',
  String body =
      'Dia tidak akan diberi tahu. Kamu masih bisa mengirim pesan dan '
      'menambahkannya lagi nanti.',
  String cancelLabel = 'Batal',
  String confirmLabel = 'Putus Teman',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) => Dialog(
      backgroundColor: PColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: PColors.textStrong,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body.replaceAll('{name}', name),
              style: const TextStyle(
                color: PColors.textSoft,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PDialogButton(
                    label: cancelLabel,
                    background: const Color(0xFF262B35),
                    foreground: PColors.text,
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PDialogButton(
                    label: confirmLabel,
                    background: PColors.dangerSolid,
                    foreground: Colors.white,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/* ═════════════ Bottom actions melayang ═════════════ */

/// Tombol aksi bawah MELAYANG (gradasi transparan → bg) ala desain profil.
/// Kiri: tombol teman (ikon saja). Kanan: "Kirim Pesan" (aksen biru).
class PBottomActions extends StatelessWidget {
  final bool isFriend;
  final bool isRequestSent;
  final VoidCallback onFriend;
  final VoidCallback? onMessage;

  const PBottomActions({
    super.key,
    required this.isFriend,
    required this.onFriend,
    this.isRequestSent = false,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final friendIcon = isFriend
        ? Icons.how_to_reg_outlined
        : (isRequestSent
              ? Icons.pending_outlined
              : Icons.person_add_alt_outlined);
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.28],
          colors: [PColors.bg.withValues(alpha: 0), PColors.bg],
        ),
      ),
      child: Row(
        children: [
          Tooltip(
            message: isFriend
                ? 'Berteman'
                : (isRequestSent ? 'Menunggu konfirmasi' : 'Tambah teman'),
            child: Material(
              color: PColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: PColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onFriend,
                child: SizedBox(
                  width: 52,
                  height: 50,
                  child: Icon(
                    friendIcon,
                    size: 22,
                    color: isFriend ? PColors.online : PColors.text,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x592F95E8),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  label: const Text('Kirim Pesan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
