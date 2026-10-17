import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../providers/riverpod/locale_provider.dart';

import '../config/theme.dart';
import 'sticker_sheet.dart';

// Sheet emoji bersama untuk input chat (private chat & room chat).
class EmojiPickerSheet {
  static const _emojis = [
    '😀',
    '😄',
    '😁',
    '😆',
    '😅',
    '😂',
    '🤣',
    '😊',
    '😍',
    '🥰',
    '😘',
    '😉',
    '😜',
    '🤪',
    '😎',
    '🥳',
    '😇',
    '🙂',
    '😐',
    '😒',
    '🙄',
    '😴',
    '🤔',
    '🥺',
    '😭',
    '😢',
    '😡',
    '😠',
    '🤬',
    '😱',
    '😨',
    '😳',
    '🙏',
    '👍',
    '👎',
    '👏',
    '🙌',
    '💪',
    '🤝',
    '✌️',
    '❤️',
    '💙',
    '💚',
    '💛',
    '🧡',
    '💜',
    '🖤',
    '💖',
    '💯',
    '🔥',
    '✨',
    '🎉',
    '🌹',
    '😌',
    '🤗',
    '🫶',
  ];

  static void show(
    BuildContext context,
    TextEditingController controller, {
    /// Bila diisi → sheet menampilkan TAB STIKER (kirim sticker) selain emoji.
    StickerBytesSender? onSendSticker,
    /// Kirim stiker koleksi server tanpa upload ulang (terus ke sheet).
    Future<void> Function(String stickerPath)? onSendStickerPath,
  }) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // contains: tinggi tetap; tab sticker butuh ruang lebih.
      isScrollControlled: onSendSticker != null,
      builder: (ctx) => onSendSticker == null
          ? SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Text(s.btnEmoji, style: AppText.bodyStrong),
                  const SizedBox(height: 4),
                  Flexible(child: _emojiGrid(controller)),
                ],
              ),
            )
          : StickerEmojiSheet(
              controller: controller,
              onSendSticker: onSendSticker,
              onSendStickerPath: onSendStickerPath,
            ),
    );
  }

  static Widget _emojiGrid(TextEditingController controller) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _emojis.length,
      itemBuilder: (_, i) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => insertAtCursor(controller, _emojis[i]),
        child: Center(
          child: Text(
            _emojis[i],
            style: const TextStyle(fontSize: AppGlyph.md),
          ),
        ),
      ),
    );
  }

  // Sisipkan emoji di posisi kursor, seleksi terpilih diganti emoji.
  /// Akses daftar emoji utk grid di sheet lain (tab bersama).
  static int get emojiCount => _emojis.length;
  static String emojiAt(int i) => _emojis[i];

  static void insertAtCursor(TextEditingController controller, String emoji) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }
}
