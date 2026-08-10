import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';

// Sheet emoji bersama untuk input chat (private chat & room chat).
class EmojiPickerSheet {
  static const _emojis = [
    '😀', '😄', '😁', '😆', '😅', '😂', '🤣', '😊',
    '😍', '🥰', '😘', '😉', '😜', '🤪', '😎', '🥳',
    '😇', '🙂', '😐', '😒', '🙄', '😴', '🤔', '🥺',
    '😭', '😢', '😡', '😠', '🤬', '😱', '😨', '😳',
    '🙏', '👍', '👎', '👏', '🙌', '💪', '🤝', '✌️',
    '❤️', '💙', '💚', '💛', '🧡', '💜', '🖤', '💖',
    '💯', '🔥', '✨', '🎉', '🌹', '😌', '🤗', '🫶',
  ];

  static void show(BuildContext context, TextEditingController controller) {
    final s = context.read<LocaleProvider>().s;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(s.btnEmoji, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Flexible(
              child: GridView.builder(
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
                  child: Center(child: Text(_emojis[i], style: const TextStyle(fontSize: 22))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sisipkan emoji di posisi kursor, seleksi terpilih diganti emoji.
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
