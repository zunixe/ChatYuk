import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../config/room_categories.dart';
import '../../../config/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/room_provider.dart';
import '../../../providers/storage_provider.dart';
import '../../../widgets/anon_prompt_dialog.dart';

const _exploreIconChoices = [
  '💬',
  '🔥',
  '🎉',
  '🎮',
  '🎵',
  '💭',
  '🤝',
  '💻',
  '🎬',
  '😂',
  '📚',
  '💘',
];

/// Sheet buat GLOBAL room — GRATIS, terbuka, TANPA password (password
/// hanya untuk Grup legacy). Ikon: emoji ATAU foto upload-an sendiri.
/// [initialCategory]: chip yang sedang aktif ('rame' → 'general').
Future<void> showCreateExploreRoomDialog(
  BuildContext context,
  String initialCategory,
) async {
  final s = context.read<LocaleProvider>().s;
  final auth = context.read<AuthProvider>();
  if (auth.isAnonymous && !auth.dummySessionActive) {
    showAnonPromptDialog(context);
    return;
  }
  final nameCtrl = TextEditingController();
  String icon = '💬';
  Uint8List? customBytes;
  String category = roomCategories.any((c) => c['id'] == initialCategory)
      ? initialCategory
      : 'general';
  bool submitting = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        Future<void> pickPhoto() async {
          final picker = ImagePicker();
          try {
            final picked = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 512,
              imageQuality: 80,
            );
            if (picked == null) return;
            final bytes = await picked.readAsBytes();
            if (!ctx.mounted) return;
            setInner(() => customBytes = bytes);
          } catch (_) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(s.errPhotoPermission)),
            );
          }
        }

        return Dialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.btnCreateRoom,
                  style: AppText.titleEmphasis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  s.createGroupSubtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(s.roomNameLabel, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  maxLength: 30,
                  style: AppText.body,
                  decoration: InputDecoration(
                    hintText: s.roomNameHint,
                    hintStyle: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(s.roomIconLabel, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: pickPhoto,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: customBytes != null
                              ? Colors.transparent
                              : AppTheme.bgScreen,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: customBytes != null
                                ? AppTheme.primary
                                : AppTheme.textSecondary.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                        child: customBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  customBytes!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              )
                            : Icon(
                                Icons.add_a_photo_rounded,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.roomIconPhotoLabel,
                            style: AppText.bodyStrong,
                          ),
                          InkWell(
                            onTap: pickPhoto,
                            child: Text(
                              customBytes != null
                                  ? s.roomIconChange
                                  : s.roomIconPick,
                              style: AppText.bodySmall.copyWith(
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _exploreIconChoices)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setInner(() {
                          icon = e;
                          customBytes = null;
                        }),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: customBytes == null && icon == e
                                ? AppTheme.primary.withValues(alpha: 0.15)
                                : AppTheme.bgScreen,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: customBytes == null && icon == e
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary.withValues(
                                      alpha: 0.3,
                                    ),
                            ),
                          ),
                          child: Text(
                            e,
                            style: TextStyle(fontSize: AppGlyph.sm),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(s.roomCategoryLabel, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  style: AppText.body,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    for (final c in roomCategories)
                      DropdownMenuItem(
                        value: '${c['id']}',
                        child: Text(
                          '${c['icon']} ${s.roomName('${c['id']}')}',
                          style: AppText.body,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setInner(() => category = v);
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.length < 3 || name.length > 30) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(s.errRoomNameLen)),
                            );
                            return;
                          }
                          setInner(() => submitting = true);
                          try {
                            var finalIcon = icon;
                            final bytes = customBytes;
                            if (bytes != null && bytes.isNotEmpty) {
                              final uid = ctx.read<AuthProvider>().uid;
                              String? path;
                              if (uid != null && uid.isNotEmpty) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(s.roomIconUploading),
                                      duration:
                                          const Duration(seconds: 2),
                                    ),
                                  );
                                }
                                path = await context
                                    .read<StorageProvider>()
                                    .uploadRoomIcon(
                                      uid: uid,
                                      base64: base64Encode(bytes),
                                    );
                              }
                              if (path != null && path.isNotEmpty) {
                                finalIcon = path;
                              } else if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text(s.roomIconUploadFail),
                                  ),
                                );
                              }
                            }
                            await ctx
                                .read<RoomProvider>()
                                .createGlobalRoom(
                                  name: name,
                                  icon: finalIcon,
                                  category: category,
                                );
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              SnackBar(
                                content: Text(s.exploreRoomCreated),
                              ),
                            );
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setInner(() => submitting = false);
                            final msg =
                                '$e'.replaceFirst('Exception: ', '');
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  msg == 'Room limit reached'
                                      ? s.errGroupLimit
                                      : msg,
                                ),
                              ),
                            );
                          }
                        },
                  child: Text(s.btnCreateRoom),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
