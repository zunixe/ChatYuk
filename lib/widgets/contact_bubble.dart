import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../core/media/chat_photo_helper.dart';
import '../core/nav_guard.dart';
import '../models/chat_contact.dart';
import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/avatar_provider.dart';
import '../providers/riverpod/chat_provider.dart' as chatRiverpod;
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/profile_lite_provider.dart';
import '../screens/user_info_screen.dart';
import 'chat_route.dart';
import 'person_avatar.dart';

/// Nama dari teks pesan kartu kontak ('📇 Nama').
///
/// Emoji 📇 = surrogate pair → JANGAN pakai substring (UTF-16 rusak →
/// "string is not well-formed UTF-16"); buang lewat runes. Fungsi MURNI agar
/// bisa diuji tanpa widget.
String contactNameFromText(String text) {
  var s = text.trim();
  final runes = s.runes;
  if (runes.isNotEmpty && runes.first == 0x1F4C7) {
    s = String.fromCharCodes(runes.skip(1));
  }
  return s.trim();
}

/// Kartu KONTAK di bubble chat (ala WhatsApp) — dua bentuk:
///
///  - **ChatYuk** (`{"t":"user","u":uid}`): payload HANYA uid → nama diambil
///    dari teks pesan (frame-1) lalu disegarkan dari profil; foto dari cache
///    avatar (menghormati privasi). Aksi: **Chat** & **Lihat profil**.
///  - **Kontak HP** (`{"t":"phone","n","p"}`): nama + nomor; aksi **Salin**,
///    **WhatsApp**, **Telepon**.
class ContactBubble extends ConsumerStatefulWidget {
  final MessageModel msg;
  final String timeStr;
  const ContactBubble({super.key, required this.msg, required this.timeStr});

  @override
  ConsumerState<ContactBubble> createState() => _ContactBubbleState();
}

class _ContactBubbleState extends ConsumerState<ContactBubble> {
  String _name = '';
  String _gender = '';
  bool _resolved = false;

  ChatContact get _c => widget.msg.contact!;

  /// Nama dari teks pesan ('📇 Nama') — sudah benar sejak frame pertama.
  String get _textName => contactNameFromText(widget.msg.text);

  @override
  void initState() {
    super.initState();
    _name = _c.isUser ? _textName : _c.name;
    if (_c.isUser) _resolve();
  }

  Future<void> _resolve() async {
    final p = await ref.read(profileLiteProvider).forUid(_c.uid);
    if (!mounted) return;
    setState(() {
      if (p != null) {
        if (p.name.isNotEmpty) _name = p.name;
        _gender = p.gender;
      }
      _resolved = true;
    });
  }

  String get _cachedAvatar =>
      ref.read(avatarProvider).cachedSyncIncludeDisk(_c.uid) ?? '';

  Future<void> _openChat() async {
    final myUid = ref.read(authProvider).uid ?? '';
    if (myUid.isEmpty) return;
    final chatId = ref.read(chatRiverpod.chatProvider.notifier).privateChatId(
          myUid,
          _c.uid,
        );
    final navKey = navKeyChat(chatId);
    if (!tryClaimNav(navKey)) return;
    await Navigator.push(
      context,
      chatRoute(
        chatId: chatId,
        otherName: _name,
        otherUid: _c.uid,
        otherGender: _gender,
      ),
    );
    releaseNav(navKey);
  }

  Future<void> _openProfile() async {
    final navKey = navKeyUser(_c.uid);
    if (!tryClaimNav(navKey)) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(userId: _c.uid, fallbackName: _name),
      ),
    );
    releaseNav(navKey);
  }

  void _copyNumber(String number) {
    Clipboard.setData(ClipboardData(text: number));
    final s = ref.read(localeProvider).s;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.contactNumberCopied)));
  }

  Future<void> _openUri(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // Lebar = lebar media chat (sama seperti bubble poll/foto) supaya kartu
    // TIDAK melebihi bubble → tidak overlap dengan jam/centang.
    final width = chatMediaWidth(MediaQuery.sizeOf(context).width);
    return SizedBox(
      width: width,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgInput,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (_c.isUser)
                    PersonAvatar(
                      uid: _c.uid,
                      name: _name,
                      gender: _gender,
                      avatarB64: _cachedAvatar,
                      size: 40,
                    )
                  else
                    _InitialsAvatar(name: _name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.isEmpty && _c.isUser
                              ? (_resolved ? s.contactUnavailable : '…')
                              : _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _c.isUser
                              ? s.contactCardLabel
                              : _c.phones.take(3).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_c.isUser && _resolved && _name.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  s.contactUnavailable,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children: _c.isUser
                      ? [
                          Expanded(
                            child: _action(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: s.btnChatContact,
                              onTap: _openChat,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _action(
                              icon: Icons.person_outline_rounded,
                              label: s.btnViewProfile,
                              onTap: _openProfile,
                            ),
                          ),
                        ]
                      : [
                          Expanded(
                            child: _action(
                              icon: Icons.copy_rounded,
                              label: s.btnCopyNumber,
                              onTap: () => _copyNumber(_c.phones.first),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _action(
                              icon: Icons.chat_rounded,
                              label: 'WhatsApp',
                              onTap: () => _openUri(
                                Uri.parse(
                                  'https://wa.me/${_digits(_c.phones.first)}',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _action(
                              icon: Icons.call_rounded,
                              label: s.btnCallContact,
                              onTap: () => _openUri(
                                Uri(scheme: 'tel', path: _c.phones.first),
                              ),
                            ),
                          ),
                        ],
                ),
              ],
            ],
          ),
        ),
        // Baris jam: inset SAMA dengan FileBubble (docs/UI_CONSISTENCY.md).
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 3, 4, 1),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              widget.timeStr,
              style: AppText.chatTime.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ],
      ),
    );
  }

  static String _digits(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      // Lebar disamakan oleh Expanded (Row) → tombol tampak rapi/sejajar.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppTheme.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar inisial untuk kontak HP (tanpa uid / tanpa foto).
class _InitialsAvatar extends StatelessWidget {
  final String name;
  const _InitialsAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final ch = name.isNotEmpty ? name.characters.first : '?';
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
      ),
      child: Text(
        ch.toUpperCase(),
        style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
      ),
    );
  }
}
