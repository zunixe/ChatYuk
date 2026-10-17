import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/theme.dart';
import '../../core/chat/chat_file.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../models/message_model.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../providers/riverpod/storage_provider.dart';
import '../chat_info_snack.dart';

/// Bubble pesan FILE/dokumen ala WhatsApp: kotak berisi ikon jenis file,
/// nama (2 baris), "PDF · 1.4 MB", tombol unduh/buka; jam + centang di
/// bawah kanan. Tap → buka (file lokal pengirim / cache / unduh dulu).
class FileBubble extends ConsumerStatefulWidget {
  final MessageModel msg;
  final String timeStr;
  final bool isMe;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  const FileBubble({
    super.key,
    required this.msg,
    required this.timeStr,
    this.isMe = false,
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  @override
  ConsumerState<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends ConsumerState<FileBubble> {
  bool _busy = false;

  String get _name => widget.msg.text.isEmpty ? 'file' : widget.msg.text;

  /// Nama file cache aman: path storage diubah jadi satu segmen.
  String _cacheName() {
    final key = widget.msg.imageData.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final safe = _name.replaceAll(RegExp(r'[/\\]'), '_');
    return '${key.hashCode.toUnsigned(32)}_$safe';
  }

  Future<void> _open() async {
    if (_busy || widget.isPending) return;
    final s = ref.read(localeProvider).s;
    final path = widget.msg.imageData;
    try {
      // 1) File lokal pengirim (baru saja dikirim dari HP ini).
      final local = ChatFile.localPathOf(path) ?? ChatFile.localPathOf(widget.msg.id);
      if (local != null && File(local).existsSync()) {
        await _launch(local);
        return;
      }
      // 2) Cache unduhan sebelumnya.
      final dir = Directory('${(await getTemporaryDirectory()).path}/chat_files');
      final f = File('${dir.path}/${_cacheName()}');
      if (!f.existsSync()) {
        if (path.isEmpty) throw Exception('no path');
        setState(() => _busy = true);
        final bytes = await ref.read(storageProvider).downloadChatFile(path);
        if (bytes == null) throw Exception('download failed');
        await dir.create(recursive: true);
        await f.writeAsBytes(bytes, flush: true);
      }
      await _launch(f.path);
    } catch (_) {
      if (mounted) showChatSnack(context, s.errOpenFile);
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _launch(String p) async {
    final r = await OpenFilex.open(p, type: ChatFile.mimeOf(_name));
    if (r.type != ResultType.done && mounted) {
      showChatSnack(context, ref.read(localeProvider).s.errOpenFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final st = ChatFile.styleOf(_name);
    final ext = ChatFile.extOf(_name).toUpperCase();
    final size = widget.msg.durationMs ?? 0;
    final meta = [
      if (ext.isNotEmpty) ext,
      if (size > 0) ChatFile.sizeLabel(size),
    ].join(' · ');
    final width = chatMediaWidth(MediaQuery.sizeOf(context).width);
    final sending = widget.isPending || widget.isQueued;

    Widget trailing;
    if (sending || _busy) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
      );
    } else {
      trailing = Icon(
        Icons.download_rounded,
        size: 20,
        color: AppTheme.textSecondary,
      );
    }

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(st.icon, color: st.color, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.chatBody.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sending
                                ? s.fileUploading
                                : (_busy ? s.fileDownloading : meta),
                            maxLines: 1,
                            style: AppText.chatCaption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 3, 4, 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.timeStr,
                  style: AppText.chatTime.copyWith(color: AppTheme.textSecondary),
                ),
                if (widget.showChecks) ...[
                  const SizedBox(width: 3),
                  Icon(
                    sending ? Icons.done : Icons.done_all,
                    size: 14,
                    color: (widget.isRead && !sending)
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
