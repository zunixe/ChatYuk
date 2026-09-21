import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../models/user_photo.dart';
import '../../../providers/locale_provider.dart';
import '../../../widgets/async_photo.dart';

/// Chip kecil di header profil (mis. "Online"/verified) — putih transparan.
class ProfileHeaderChip extends StatelessWidget {
  final String label;
  const ProfileHeaderChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppText.label.copyWith(
          color: Colors.white,
          letterSpacing: 0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Statistik profil (nilai besar + label) yang bisa di-tap.
class ProfileStat extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;
  const ProfileStat({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          children: [
            Text(
              value < 0 ? '—' : '$value',
              style: AppText.titleEmphasis.copyWith(color: AppTheme.primary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label kecil di atas kartu section.
class ProfileSectionLabel extends StatelessWidget {
  final String label;
  const ProfileSectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppText.label.copyWith(color: AppTheme.textSecondary),
    );
  }
}

/// Kartu section berlatar bgCard + shadow halus.
class ProfileSectionCard extends StatelessWidget {
  final List<Widget> children;
  const ProfileSectionCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// Baris info ikon + label + nilai.
///
/// Satu-satunya bentuk baris info di kartu Profil. SEMUA baris (Status,
/// Username, User ID, About) WAJIB memakai widget ini supaya padding,
/// ukuran ikon, jarak, dan gaya teks konsisten — dulu Username & About
/// dibuat manual dengan padding berbeda sehingga ikon/teksnya tidak
/// sejajar dengan baris lain dan tingginya tidak sama.
class ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  /// Widget di ujung kanan (mis. tombol edit). Null = tidak ada.
  final Widget? trailing;

  /// Override gaya nilai (mis. placeholder abu saat teks kosong).
  final TextStyle? valueStyle;

  /// Batas baris nilai. Null = bebas (teks panjang seperti About).
  final int? valueMaxLines;

  const ProfileInfoTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailing,
    this.valueStyle,
    this.valueMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Sama untuk SEMUA baris di kartu profil/settings: horizontal 4 +
      // vertical 6, sehingga ikon, teks, dan divider (indent 52) sejajar.
      // Ikon 36 + jarak 12 + padding 4 = 52 = indent divider.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: valueStyle ?? AppText.bodyStrong,
                  maxLines: valueMaxLines,
                  overflow:
                      valueMaxLines != null ? TextOverflow.ellipsis : null,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Viewer foto profil full-screen (PageView + zoom).
class ProfilePhotoViewerScreen extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const ProfilePhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<ProfilePhotoViewerScreen> createState() =>
      _ProfilePhotoViewerScreenState();
}

class _ProfilePhotoViewerScreenState extends State<ProfilePhotoViewerScreen> {
  int _index = 0;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.photos.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) => Center(
          child: InteractiveViewer(
            maxScale: 4,
            child: AsyncPhotoViewer(base64: widget.photos[i].photo),
          ),
        ),
      ),
    );
  }
}

/// Format angka dengan pemisah ribuan (1000 -> 1.000).
String formatPoints(int n) {
  final digits = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buf.write(digits[i]);
    final rem = digits.length - 1 - i;
    if (rem > 0 && rem % 3 == 0) buf.write('.');
  }
  return buf.toString();
}

/// Item grid aksi cepat profil.
class ProfileActionItem {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const ProfileActionItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
}

/// Grid aksi cepat — ikon bulat + label di bawahnya, rapi tanpa bubble.
class ProfileActionGrid extends StatelessWidget {
  final List<ProfileActionItem> actions;
  const ProfileActionGrid({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(a.icon, size: 22, color: a.color),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tile setelan ukuran font chat (slider) — berlaku untuk bubble chat,
/// nama pengirim, dan jam pesan. Tersimpan lokal (SharedPreferences) dan
/// langsung terlihat di preview.
class ProfileChatFontTile extends StatefulWidget {
  const ProfileChatFontTile({super.key});

  @override
  State<ProfileChatFontTile> createState() => _ProfileChatFontTileState();
}

class _ProfileChatFontTileState extends State<ProfileChatFontTile> {
  // Slider bekerja pada INDEX step (0..steps) → label berupa ANGKA ukuran
  // font (pt), lebih rapat & intuitif daripada persen.
  late int _step = ChatTextScale.stepIndex;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final mult = ChatTextScale.multOfStep(_step);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.format_size_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.labelChatFontSize,
                      style: AppText.bodyStrong.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      s.descChatFontSize,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                ChatTextScale.labelOf(mult),
                style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
              ),
            ],
          ),
          // Preview bubble mengikuti ukuran.
          Container(
            margin: const EdgeInsets.only(top: 8, left: 48, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgScreen,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(
              s.chatFontPreview,
              // Ukuran contoh mengikuti NILAI SLIDER saat ini (bukan current
              // tersimpan) → tidak ada jeda/beda antara geser dan contoh.
              style: AppText.chatBodyAt(
                ChatTextScale.ptOf(mult),
              ).copyWith(color: AppTheme.textPrimary),
            ),
          ),
          Slider(
            value: _step.toDouble(),
            min: 0,
            max: ChatTextScale.steps.toDouble(),
            divisions: ChatTextScale.steps,
            label: ChatTextScale.labelOf(mult),
            activeColor: AppTheme.primary,
            onChanged: (v) => setState(() => _step = v.round()),
            onChangeEnd: (v) async {
              await ChatTextScale.set(ChatTextScale.multOfStep(v.round()));
              // Subtree chat rebuild via ChatTextScale.notifier (app.dart).
            },
          ),
          // Skala angka rapat (semua tingkat) supaya user lihat pilihan.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i <= ChatTextScale.steps; i++)
                  Text(
                    ChatTextScale.labelOf(ChatTextScale.multOfStep(i)),
                    style: AppText.caption.copyWith(
                      color: i == _step
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      fontWeight:
                          i == _step ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
