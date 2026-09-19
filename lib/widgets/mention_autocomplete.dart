import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../utils/mention.dart';

/// Panel saran mention `@` yang mengambang DI ATAS composer (tidak menggeser
/// layout chat). Dipakai composer private chat, room, dan grup.
///
/// Panel muncul saat kursor berada di dalam token `@…` dan menutup begitu
/// user mengetik spasi / baris baru. Pemilihan item menulis ulang token
/// parsial menjadi `@Nama ` dan menempatkan kursor sesudahnya.
class MentionAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final List<Mention> candidates;

  /// `@all` hanya untuk private room/grup oleh owner/admin.
  final bool allowAll;
  final List<Mention> allExpansion;

  const MentionAutocomplete({
    super.key,
    required this.controller,
    required this.candidates,
    this.allowAll = false,
    this.allExpansion = const [],
  });

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete> {
  ({int start, String query})? _token;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant MentionAutocomplete old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final value = widget.controller.value;
    final token = value.selection.isValid
        ? activeMentionToken(value.text, value.selection.baseOffset)
        : null;
    if (token?.start == _token?.start && token?.query == _token?.query) return;
    if (!mounted) return;
    setState(() {
      _token = token;
      _selected = 0;
    });
  }

  List<_Item> get _items {
    final out = <_Item>[];
    if (widget.allowAll) {
      out.add(const _Item.all());
    }
    for (final m in filterCandidates(widget.candidates, _token?.query ?? '')) {
      out.add(_Item.user(m));
    }
    return out;
  }

  void _pick(_Item item) {
    final token = _token;
    if (token == null) return;
    final text = widget.controller.text;
    final tokenText = item.isAll ? '@all' : '@${item.mention!.name}';
    final before = text.substring(0, token.start);
    final after = text.substring(
      (token.start + 1 + token.query.length).clamp(0, text.length),
    );
    final insert = '$tokenText ';
    final next = '$before$insert$after';
    final caret = before.length + insert.length;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() => _token = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null) return const SizedBox.shrink();
    final s = context.read<LocaleProvider>().s;
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();
    final selected = _selected.clamp(0, items.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.mentionHint(_token!.query),
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final isSel = i == selected;
                  return InkWell(
                    onTap: () => _pick(item),
                    child: Container(
                      color: isSel
                          ? AppTheme.primary.withValues(alpha: 0.10)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: item.isAll
                                ? AppTheme.primary
                                : AppTheme.primary.withValues(alpha: 0.15),
                            child: Text(
                              item.isAll
                                  ? '@'
                                  : (item.mention!.name.isEmpty
                                        ? '?'
                                        : item.mention!.name[0].toUpperCase()),
                              style: TextStyle(
                                color: item.isAll
                                    ? Colors.white
                                    : AppTheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppGlyph.avatarInitial(32),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.isAll ? s.mentionAll : item.mention!.name,
                              style: AppText.bodyStrong.copyWith(
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isAll)
                            Text(
                              '@all',
                              style: AppText.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Item {
  final Mention? mention;
  final bool isAll;
  const _Item.user(Mention this.mention) : isAll = false;
  const _Item.all() : isAll = true, mention = null;
}
