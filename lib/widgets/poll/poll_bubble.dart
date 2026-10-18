import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../models/chat_poll.dart';
import '../../models/message_model.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../providers/riverpod/poll_provider.dart';
import '../chat_info_snack.dart';

/// Bubble POLL ala WhatsApp (private chat).
///
/// Ringan & tanpa kedip:
/// - Isi (pertanyaan/opsi) dari `msg.poll` (ikut cache pesan) → frame pertama
///   langsung lengkap; ukuran TIDAK berubah saat hasil datang (bar & kolom
///   angka selalu ada, lebar tetap).
/// - Hasil di-request LAZY saat bubble di-mount (dikumpulkan 1 RPC) dan
///   didengar per-bubble (ValueListenable) → list chat tak ikut rebuild.
class PollBubble extends ConsumerStatefulWidget {
  final MessageModel msg;
  /// chatId (private) — diabaikan bila [roomId] diisi.
  final String chatId;
  /// roomId (grup / global room): poll memakai RPC + tabel room_poll_votes.
  final String roomId;
  final String timeStr;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  const PollBubble({
    super.key,
    required this.msg,
    this.chatId = '',
    this.roomId = '',
    required this.timeStr,
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  @override
  ConsumerState<PollBubble> createState() => _PollBubbleState();
}

class _PollBubbleState extends ConsumerState<PollBubble> {
  // Poll private & poll room punya tabel/RPC sendiri → controller TERPISAH
  // (id pesan antar tabel bisa sama; satu controller akan saling menimpa).
  late final PollController _ctl = widget.roomId.isNotEmpty
      ? ref.read(roomPollProvider)
      : ref.read(pollProvider);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctl.request(widget.msg.id);
    if (widget.roomId.isNotEmpty) {
      _ctl.attachRoom(widget.roomId);
    } else if (widget.chatId.isNotEmpty) {
      _ctl.attachChat(widget.chatId);
    }
  }

  @override
  void didUpdateWidget(PollBubble old) {
    super.didUpdateWidget(old);
    // pending → id server: minta hasil untuk id baru.
    if (old.msg.id != widget.msg.id) _ctl.request(widget.msg.id);
  }

  Future<void> _tap(ChatPoll poll, PollResult? r, int i) async {
    if (_busy || widget.isPending || widget.msg.id.startsWith('pending-')) {
      return;
    }
    final mine = r?.mine ?? const <int>{};
    final next = <int>{...mine};
    if (poll.multi) {
      next.contains(i) ? next.remove(i) : next.add(i);
    } else {
      next
        ..clear()
        ..addAll(mine.contains(i) ? const <int>{} : {i});
    }
    _busy = true;
    final ok = await _ctl.vote(widget.msg.id, poll, next);
    _busy = false;
    if (!ok && mounted) {
      showChatSnack(context, ref.read(localeProvider).s.errVotePoll);
    }
  }

  @override
  Widget build(BuildContext context) {
    final poll = widget.msg.poll!;
    final s = ref.watch(localeProvider).s;
    final width = chatMediaWidth(MediaQuery.sizeOf(context).width);
    return SizedBox(
      width: width,
      child: ValueListenableBuilder<PollResult?>(
        valueListenable: _ctl.listen(widget.msg.id),
        builder: (_, r, _) {
          final total = r?.voters ?? 0;
          final max = r?.maxCount ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                poll.question,
                style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    poll.multi ? Icons.checklist_rounded : Icons.check_rounded,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    poll.multi ? s.pollSelectMany : s.pollSelectOne,
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < poll.options.length; i++)
                _OptionRow(
                  label: poll.options[i],
                  multi: poll.multi,
                  selected: r?.mine.contains(i) ?? false,
                  count: r == null || i >= r.counts.length ? null : r.counts[i],
                  fraction: (r == null || max == 0 || i >= r.counts.length)
                      ? 0
                      : r.counts[i] / max,
                  onTap: () => _tap(poll, r, i),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r == null ? '' : s.pollVotes(total),
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    widget.timeStr,
                    style: AppText.chatTime.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (widget.showChecks) ...[
                    const SizedBox(width: 3),
                    Icon(
                      (widget.isPending || widget.isQueued)
                          ? Icons.done
                          : Icons.done_all,
                      size: 14,
                      color: (widget.isRead &&
                              !widget.isPending &&
                              !widget.isQueued)
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final bool multi;
  final bool selected;
  final int? count;
  final double fraction;
  final VoidCallback onTap;
  const _OptionRow({
    required this.label,
    required this.multi,
    required this.selected,
    required this.count,
    required this.fraction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = AppTheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? (multi ? Icons.check_box_rounded : Icons.check_circle_rounded)
                  : (multi
                        ? Icons.check_box_outline_blank_rounded
                        : Icons.radio_button_unchecked_rounded),
              size: 20,
              color: selected ? on : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AppText.chatBody.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      // Lebar TETAP → angka datang tanpa menggeser label.
                      SizedBox(
                        width: 32,
                        child: Text(
                          count == null ? '' : '$count',
                          textAlign: TextAlign.right,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Bar SELALU ada (tinggi tetap) — mulai 0, beranimasi ke nilai.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            widthFactor: fraction.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: on),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
