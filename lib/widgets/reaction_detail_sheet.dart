import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/message_reaction_service.dart';
import 'profile_avatar.dart';

Future<void> showReactionDetailSheet(
  BuildContext context, {
    required String chatType,
    required String messageId,
    required String myUid,
    required String myName,
    Map<String, String> knownNames = const {},
  }) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ReactionDetailSheet(
      chatType: chatType,
      messageId: messageId,
      myUid: myUid,
      myName: myName,
      knownNames: knownNames,
    ),
  );
}

class _Reactor {
  final String userId;
  final String emoji;
  final String name;
  final bool isMe;
  const _Reactor({
    required this.userId,
    required this.emoji,
    required this.name,
    required this.isMe,
  });
}

class _ReactionDetailSheet extends StatefulWidget {
  final String chatType;
  final String messageId;
  final String myUid;
  final String myName;
  final Map<String, String> knownNames;
  const _ReactionDetailSheet({
    required this.chatType,
    required this.messageId,
    required this.myUid,
    required this.myName,
    required this.knownNames,
  });

  @override
  State<_ReactionDetailSheet> createState() => _ReactionDetailSheetState();
}

class _ReactionDetailSheetState extends State<_ReactionDetailSheet> {
  List<_Reactor> _reactors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = MessageReactionService.instance;
    final rows = await svc.fetchReactors(
      chatType: widget.chatType,
      messageId: widget.messageId,
    );
    final unknown = {
      for (final r in rows)
        if (r['userId']! != widget.myUid &&
            (widget.knownNames[r['userId']] ?? '').isEmpty)
          r['userId']!,
    };
    final nicks = await svc.fetchNicknames(unknown);
    if (!mounted) return;
    setState(() {
      _reactors = [
        for (final r in rows)
          _Reactor(
            userId: r['userId']!,
            emoji: r['emoji']!,
            name: r['userId'] == widget.myUid
                ? widget.myName
                : (widget.knownNames[r['userId']] ??
                    nicks[r['userId']] ??
                    ''),
            isMe: r['userId'] == widget.myUid,
          ),
      ];
      _loading = false;
    });
    if (_reactors.isEmpty && mounted) Navigator.pop(context);
  }

  Future<void> _remove(_Reactor r) async {
    final s = context.read<LocaleProvider>().s;
    final ok = await MessageReactionService.instance.removeReaction(
      chatType: widget.chatType,
      messageId: widget.messageId,
      emoji: r.emoji,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgReactionRemoveFailed)),
      );
      return;
    }
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final counts = <String, int>{};
    for (final r in _reactors) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final total = _reactors.length;
    final mine = {
      for (final r in _reactors)
        if (r.isMe) r.emoji,
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(s.reactionsTitle(total), style: AppText.bodyStrong),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else ...[
              if (counts.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final e in counts.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mine.contains(e.key)
                                  ? Color.alphaBlend(
                                      AppTheme.primary.withValues(alpha: 0.2),
                                      AppTheme.bgCard,
                                    )
                                  : AppTheme.bgInput,
                              borderRadius: BorderRadius.circular(20),
                              border: mine.contains(e.key)
                                  ? Border.all(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.5),
                                    )
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  e.key,
                                  style:
                                      TextStyle(fontSize: AppGlyph.md),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${e.value}',
                                  style: AppText.bodyStrong.copyWith(
                                    color: mine.contains(e.key)
                                        ? AppTheme.primary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _reactors.length,
                  itemBuilder: (_, i) {
                    final r = _reactors[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ProfileAvatar(
                        uid: r.userId,
                        name: r.name.isNotEmpty ? r.name : '?',
                        size: 40,
                      ),
                      title: Text(
                        r.isMe ? s.labelYou : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: r.isMe
                          ? Text(
                              s.msgTapToRemove,
                              style: AppText.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            )
                          : null,
                      trailing: Text(
                        r.emoji,
                        style: TextStyle(fontSize: AppGlyph.lg),
                      ),
                      onTap: r.isMe ? () => _remove(r) : null,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
