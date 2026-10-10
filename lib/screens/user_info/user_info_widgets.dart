import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../models/user_photo.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../widgets/async_photo.dart';

class UserChatIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const UserChatIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    return Tooltip(
      message: s.btnChatNow,
      child: Material(
        color: AppTheme.primary.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.chat_bubble_rounded,
              size: 18,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class UserPhotoViewer extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const UserPhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<UserPhotoViewer> createState() => UserPhotoViewerState();
}

class UserPhotoViewerState extends State<UserPhotoViewer> {
  late final PageController _controller;
  late int _index;

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
      // SafeArea: foto portrait tinggi TANPA ini mencapai belakang menu
      // navigasi bawah (kasus sama seperti preview video chat).
      body: SafeArea(
        child: PageView.builder(
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
      ),
    );
  }
}

/// Loading instan: nama + inisial langsung tampil dari fallback, spinner
/// kecil di bawah — tidak ada layar kosong muter-muter.
class UserInfoLoadingPlaceholder extends StatelessWidget {
  final String name;
  const UserInfoLoadingPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.accent,
            child: Text(
              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: AppGlyph.avatarInitial(100),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name.isNotEmpty ? name : '…',
            style: AppText.headline.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gagal total (timeout/network) — pesan jelas + tombol coba lagi.
class UserInfoLoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const UserInfoLoadErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              s.msgServerError,
              style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              s.msgServerErrorHint,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(s.btnRetry),
            ),
          ],
        ),
      ),
    );
  }
}
