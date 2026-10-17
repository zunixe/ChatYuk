import 'package:flutter/material.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../models/chat_poll.dart';

/// Sheet "Buat polling" ala WhatsApp: pertanyaan, opsi (otomatis bertambah
/// saat opsi terakhir diisi, maks 12), toggle beberapa jawaban, tombol kirim.
class PollComposerSheet extends StatefulWidget {
  final S s;
  const PollComposerSheet({super.key, required this.s});

  static Future<ChatPoll?> show(BuildContext context, {required S s}) {
    return showModalBottomSheet<ChatPoll>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PollComposerSheet(s: s),
    );
  }

  @override
  State<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<PollComposerSheet> {
  final _q = TextEditingController();
  final List<TextEditingController> _opts = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multi = false;

  S get s => widget.s;

  @override
  void dispose() {
    _q.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    super.dispose();
  }

  void _onOptionChanged(int i) {
    // Opsi terakhir terisi → tambah kolom kosong baru (maks 12).
    final last = _opts.last.text.trim();
    if (i == _opts.length - 1 &&
        last.isNotEmpty &&
        _opts.length < ChatPoll.maxOptions) {
      setState(() => _opts.add(TextEditingController()));
    } else {
      setState(() {});
    }
  }

  List<String> get _cleanOptions {
    final seen = <String>{};
    final out = <String>[];
    for (final c in _opts) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  bool get _valid =>
      _q.text.trim().isNotEmpty && _cleanOptions.length >= ChatPoll.minOptions;

  void _submit() {
    final q = _q.text.trim();
    final o = _cleanOptions;
    if (q.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(s.pollNeedQuestion)));
      return;
    }
    if (o.length < ChatPoll.minOptions) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(s.pollNeedOptions)));
      return;
    }
    Navigator.of(context).pop(ChatPoll(question: q, options: o, multi: _multi));
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: AppTheme.bgInput,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        // Tombol kirim di HEADER (bukan FAB melayang) — dulu FAB menutupi
        // switch "beberapa jawaban" saat keyboard terbuka (cek di HP).
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: AppTheme.textPrimary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    s.pollCreateTitle,
                    style: AppText.title.copyWith(color: AppTheme.textPrimary),
                  ),
                ),
                IconButton.filled(
                  key: const ValueKey('poll_send'),
                  onPressed: _submit,
                  style: IconButton.styleFrom(
                    backgroundColor: _valid
                        ? AppTheme.primary
                        : AppTheme.textSecondary.withValues(alpha: 0.4),
                  ),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.pollQuestion, style: AppText.label),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('poll_question'),
              controller: _q,
              autofocus: true,
              maxLength: ChatPoll.maxQuestionLen,
              minLines: 1,
              maxLines: 3,
              style: AppText.body,
              onChanged: (_) => setState(() {}),
              decoration: _deco(s.pollQuestionHint),
            ),
            const SizedBox(height: 16),
            Text(s.pollOptions, style: AppText.label),
            const SizedBox(height: 6),
            for (var i = 0; i < _opts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  key: ValueKey('poll_option_$i'),
                  controller: _opts[i],
                  maxLength: ChatPoll.maxOptionLen,
                  style: AppText.body,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _onOptionChanged(i),
                  decoration: _deco(s.pollOptionHint(i + 1)),
                ),
              ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.pollAllowMultiple, style: AppText.bodyStrong),
              value: _multi,
              onChanged: (v) => setState(() => _multi = v),
            ),
          ],
        ),
      ),
    );
  }
}
