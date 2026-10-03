import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../utils.dart';
import 'gender_avatar.dart';

/// Bottom sheet bagikan postingan timeline ala Threads.
///
/// Susunan dari atas ke bawah:
/// 1. Preview penulis post (avatar + nama + cuplikan teks).
/// 2. Kolom search untuk cari user.
/// 3. Deretan avatar user ChatYuk (horizontal) — ketuk untuk bagikan
///    langsung ke chat pribadi user tersebut.
/// 4. Deretan aplikasi eksternal (WhatsApp, Telegram, Salin Tautan, Lainnya).
Future<void> showPostShareSheet({
  required BuildContext context,
  required String authorUid,
  required String authorName,
  required String authorGender,
  required String snippet,
  required String shareText,
  required String shareSubject,
  required Future<List<XFile>> Function() buildFiles,
  required Future<bool> Function(UserModel user) onShareToUser,
  required Future<void> Function() onExternalShared,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PostShareSheet(
      authorUid: authorUid,
      authorName: authorName,
      authorGender: authorGender,
      snippet: snippet,
      shareText: shareText,
      shareSubject: shareSubject,
      buildFiles: buildFiles,
      onShareToUser: onShareToUser,
      onExternalShared: onExternalShared,
    ),
  );
}

class _PostShareSheet extends StatefulWidget {
  final String authorUid;
  final String authorName;
  final String authorGender;
  final String snippet;
  final String shareText;
  final String shareSubject;
  final Future<List<XFile>> Function() buildFiles;
  final Future<bool> Function(UserModel user) onShareToUser;
  final Future<void> Function() onExternalShared;

  const _PostShareSheet({
    required this.authorUid,
    required this.authorName,
    required this.authorGender,
    required this.snippet,
    required this.shareText,
    required this.shareSubject,
    required this.buildFiles,
    required this.onShareToUser,
    required this.onExternalShared,
  });

  @override
  State<_PostShareSheet> createState() => _PostShareSheetState();
}

class _PostShareSheetState extends State<_PostShareSheet> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  List<UserModel> _users = const [];
  String? _sendingUid;
  // Aksi aplikasi yang sedang jalan ('whatsapp'/'telegram'/'more').
  // Spinner hanya tampil di tombol itu; tombol lain cukup nonaktif.
  String? _busyAction;
  bool get _busyExternal => _busyAction != null;

  @override
  void initState() {
    super.initState();
    // Snapshot sekali — daftar tidak ikut rebuild tiap update presence
    // supaya kolom search tidak kehilangan fokus.
    final myUid = context.read<AuthProvider>().uid ?? '';
    final all = context.read<OnlineUsersProvider>().users;
    _users = [
      for (final u in all)
        if (u.uid.isNotEmpty && u.uid != myUid) u,
    ];
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _q = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserModel> get _filtered {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return [
      for (final u in _users)
        if (u.nickname.toLowerCase().contains(q)) u,
    ];
  }

  Future<void> _shareToUser(UserModel user) async {
    if (_sendingUid != null) return;
    setState(() => _sendingUid = user.uid);
    bool ok = false;
    try {
      ok = await widget.onShareToUser(user);
    } catch (e) {
      dlog('[PostShareSheet] share ke user error: $e');
    }
    if (!mounted) return;
    setState(() => _sendingUid = null);
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _afterExternal(bool success) async {
    if (!success || !mounted) return;
    try {
      await widget.onExternalShared();
    } catch (e) {
      dlog('[PostShareSheet] counter share error: $e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _shareWhatsApp() async {
    if (_busyExternal) return;
    setState(() => _busyAction = 'whatsapp');
    try {
      final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(widget.shareText)}',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        await _afterExternal(true);
      } else {
        final r = await Share.share(
          widget.shareText,
          subject: widget.shareSubject,
        );
        await _afterExternal(r.status == ShareResultStatus.success);
      }
    } catch (e) {
      dlog('[PostShareSheet] WhatsApp error: $e');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _shareTelegram() async {
    if (_busyExternal) return;
    setState(() => _busyAction = 'telegram');
    try {
      final uri = Uri.parse(
        'https://t.me/share/url?url=${Uri.encodeComponent('https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk')}&text=${Uri.encodeComponent(widget.shareText)}',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        await _afterExternal(true);
      } else {
        final r = await Share.share(
          widget.shareText,
          subject: widget.shareSubject,
        );
        await _afterExternal(r.status == ShareResultStatus.success);
      }
    } catch (e) {
      dlog('[PostShareSheet] Telegram error: $e');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _copyLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.shareText));
      if (!mounted) return;
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.shareCopied)));
      await _afterExternal(true);
    } catch (e) {
      dlog('[PostShareSheet] salin tautan error: $e');
    }
  }

  Future<void> _shareMore() async {
    if (_busyExternal) return;
    setState(() => _busyAction = 'more');
    try {
      final files = await widget.buildFiles();
      ShareResult r;
      if (files.isEmpty) {
        r = await Share.share(widget.shareText, subject: widget.shareSubject);
      } else {
        r = await Share.shareXFiles(
          files,
          text: widget.shareText,
          subject: widget.shareSubject,
        );
      }
      await _afterExternal(r.status == ShareResultStatus.success);
    } catch (e) {
      dlog('[PostShareSheet] share lainnya error: $e');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final users = _filtered;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _previewHeader(s),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              style: AppText.body.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: s.shareSearchUsers,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 92,
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        s.noResults,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: users.length,
                      separatorBuilder: (a, b) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => _userItem(users[i], s),
                    ),
            ),
            const Divider(height: 24),
            Text(
              s.shareViaApps,
              style: AppText.label.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _appItem(
                  label: 'WhatsApp',
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFF25D366),
                  onTap: _shareWhatsApp,
                  busy: _busyAction == 'whatsapp',
                ),
                _appItem(
                  label: 'Telegram',
                  icon: Icons.send_rounded,
                  color: const Color(0xFF229ED9),
                  onTap: _shareTelegram,
                  busy: _busyAction == 'telegram',
                ),
                _appItem(
                  label: s.shareCopyLink,
                  icon: Icons.link_rounded,
                  color: AppTheme.primary,
                  onTap: _copyLink,
                  busy: false,
                ),
                _appItem(
                  label: s.shareMoreApps,
                  icon: Icons.more_horiz_rounded,
                  color: AppTheme.textSecondary,
                  onTap: _shareMore,
                  busy: _busyAction == 'more',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewHeader(S s) {
    return Row(
      children: [
        GenderAvatar(
          uid: widget.authorUid,
          name: widget.authorName,
          gender: widget.authorGender,
          size: 40,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.authorName,
                style: AppText.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.snippet.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.snippet,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _userItem(UserModel user, S s) {
    final sending = _sendingUid == user.uid;
    return GestureDetector(
      onTap: sending ? null : () => _shareToUser(user),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                GenderAvatar(
                  uid: user.uid,
                  name: user.nickname,
                  gender: user.gender,
                  size: 56,
                ),
                if (sending)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              user.nickname,
              style: AppText.caption.copyWith(color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _appItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool busy,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busyExternal ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.bgInput,
              ),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppText.caption.copyWith(color: AppTheme.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
