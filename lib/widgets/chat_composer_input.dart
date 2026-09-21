import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../mixins/voice_recorder_mixin.dart';
import '../providers/locale_provider.dart';
import '../utils/mention.dart';
import 'mic_record_button.dart';
import 'mention_autocomplete.dart';
import 'chat_ui_shared.dart';
import 'composer_link_preview.dart';
import 'emoji_picker_sheet.dart';

class ChatComposerInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSend;
  final bool showAttachRow;
  final VoidCallback onToggleAttach;
  final VoidCallback onTakePhoto;
  final VoidCallback onSendPhoto;
  final VoidCallback onSendViewOnce;
  final String? pendingPhotoBase64;
  final VoidCallback? onCancelPhoto;
  final VoidCallback? onOpenGiftPanel;
  final void Function(String filePath, int durationMs)? onSendVoice;
  /// Sinyal 'sedang merekam' (private pakai typing kind=recording).
  final VoidCallback? onRecordingSignal;
  /// Sinyal 'sedang mengetik' (private/room beda saluran).
  final VoidCallback? onTyping;
  /// Kirim koin (khusus chat 1:1). null = chip tidak tampil.
  final VoidCallback? onSendCoin;
  final List<Mention> mentionCandidates;
  final bool mentionAllowAll;
  final List<Mention> mentionAllExpansion;
  /// Warna isi pill composer (dan bordernya). Default `bgCard` — cocok untuk
  /// private chat yang punya background foto (scaffold transparan). Room/grup
  /// memakai scaffold `bgCard`, jadi kirim `bgInput` supaya pill tetap kontras.
  final Color? inputFillColor;
  const ChatComposerInput({
    required this.controller,
    this.focusNode,
    required this.onSend,
    required this.showAttachRow,
    required this.onToggleAttach,
    required this.onTakePhoto,
    required this.onSendPhoto,
    required this.onSendViewOnce,
    this.pendingPhotoBase64,
    this.onCancelPhoto,
    this.onOpenGiftPanel,
    this.onSendVoice,
    this.onRecordingSignal,
    this.onTyping,
    this.onSendCoin,
    this.mentionCandidates = const [],
    this.mentionAllowAll = false,
    this.mentionAllExpansion = const [],
    this.inputFillColor,
  });

  @override
  State<ChatComposerInput> createState() => _ChatComposerInputState();
}

class _ChatComposerInputState extends State<ChatComposerInput>
    with VoiceRecorderMixin<ChatComposerInput> {
  Uint8List? _decodedPhoto;

  // ── Kontrak VoiceRecorderMixin ──
  @override
  void voiceSendRecordingSignal() => widget.onRecordingSignal?.call();

  @override
  Future<void> voiceFinishRecording(String path, int durationMs) async {
    widget.onSendVoice?.call(path, durationMs);
  }

  @override
  String voicePermissionMessage() =>
      context.read<LocaleProvider>().s.errVoicePermission;

  @override
  String voiceTooShortMessage() =>
      context.read<LocaleProvider>().s.errVoiceTooShort;








  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _decodePhoto();
  }

  @override
  void didUpdateWidget(covariant ChatComposerInput old) {
    super.didUpdateWidget(old);
    if (old.pendingPhotoBase64 != widget.pendingPhotoBase64) _decodePhoto();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    disposeVoiceRecorder();
    super.dispose();
  }

  void _decodePhoto() {
    final b64 = widget.pendingPhotoBase64;
    if (b64 == null) {
      _decodedPhoto = null;
    } else {
      try {
        _decodedPhoto = base64Decode(b64);
      } catch (_) {
        _decodedPhoto = null;
      }
    }
  }

  void _onChanged() {
    // Rebuild ditangani ValueListenableBuilder (tombol send/mic) — di sini
    // hanya sinyal typing ke lawan (throttle di sisi layar).
    widget.onTyping?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        // Transparan: background chat (gambar/blur) tetap terlihat di
        // belakang composer. Header card di dalam tetap bgCard.
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_decodedPhoto != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Image.memory(
                        _decodedPhoto!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        // Preview tinggi 150px — cap decode agar tidak
                        // raster foto asli (bisa 4000px) utk preview mungil.
                        cacheHeight: 450,
                        gaplessPlayback: true,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: widget.onCancelPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!voiceRecording)
              MentionAutocomplete(
                controller: widget.controller,
                candidates: widget.mentionCandidates,
                allowAll: widget.mentionAllowAll,
                allExpansion: widget.mentionAllExpansion,
              ),
            ComposerLinkPreview(controller: widget.controller),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.isDark
                        ? Colors.transparent
                        : AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => EmojiPickerSheet.show(
                      context,
                      widget.controller,
                    ),
                    icon: Icon(Icons.emoji_emotions_outlined, size: 20),
                    color: AppTheme.isDark ? AppTheme.primary : Colors.white,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: 2),
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 132),
                    decoration: BoxDecoration(
                      color: widget.inputFillColor ?? AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: widget.inputFillColor ?? AppTheme.bgCard,
                        width: 1,
                      ),
                    ),
                    // Isi card di-swap: ketik pesan ↔ rekam voice.
                    // Ukuran & posisi card 100% identik karena
                    // container-nya yang sama. Tinggi 48 = tinggi
                    // konten ketik (icon +/📷 48px).
                    child: voiceRecording
                        ? SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                Icon(Icons.mic_rounded, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  voiceSeconds < 60
                                      ? '${voiceSeconds.toString().padLeft(2, '0')}s'
                                      : '${(voiceSeconds ~/ 60).toString().padLeft(2, '0')}:${(voiceSeconds % 60).toString().padLeft(2, '0')}',
                                  style: AppText.chatBodyStrong.copyWith(color: Colors.red),
                                ),
                                const Spacer(),
                                if (!voiceLocked || voicePickUp) ...[
                                  Icon(
                                    Icons.keyboard_arrow_left_rounded,
                                    color: AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                  Text(
                                    s.hintSlideToCancel,
                                    style: AppText.chatCaption.copyWith(color: AppTheme.textSecondary),
                                  ),
                                ] else ...[
                                  GestureDetector(
                                    onTap: () => voicePaused
                                        ? resumeVoiceRecord()
                                        : pauseVoiceRecord(),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        voicePaused
                                            ? Icons.play_arrow_rounded
                                            : Icons.pause_rounded,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 16),
                              ],
                            ),
                          )
                        : Row(
                            // Center: teks & ikon (+ / kamera) duduk di tengah
                            // tinggi pill rounded — bukan menempel bawah.
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: widget.controller,
                                  focusNode: widget.focusNode,
                                  style: AppText.chatBody,
                                  decoration: InputDecoration(
                                    hintText: s.hintTypeMessage,
                                    hintStyle: AppText.chatBody.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.newline,
                                  onChanged: (_) => widget.onTyping?.call(),
                                  onSubmitted: (_) => widget.onSend(),
                                  minLines: 1,
                                  maxLines: null,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization: TextCapitalization.sentences,
                                ),
                              ),
                              ChatIconButton(
                                icon: widget.showAttachRow
                                    ? Icons.close
                                    : Icons.add_circle_outline,
                                open: widget.showAttachRow,
                                onTap: widget.onToggleAttach,
                                tooltip: s.menuSendPhoto,
                              ),
                              // Tombol gift HANYA bila sistem koin aktif —
                              // +, gift, kamera mepet tanpa jeda.
                              if (widget.onOpenGiftPanel != null) ...[
                                ChatIconButton(
                                  open: false,
                                  onTap: widget.onOpenGiftPanel!,
                                  tooltip: s.giftTitle,
                                  icon: Icons.card_giftcard_outlined,
                                ),
                              ],
                              ChatIconButton(
                                open: false,
                                onTap: widget.onTakePhoto,
                                tooltip: s.menuTakePhoto,
                                icon: Icons.photo_camera_outlined,
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Rebuild granular: hanya area tombol mic/send yang rebuild
                // saat teks berubah — seluruh composer tidak ikut.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  // HANYA currentChild — previousChildren dibuang supaya
                  // tidak ada DUA bulatan bertumpuk saat cross-fade
                  // (sumber blink biru/gembok saat rekaman dibatalkan).
                  layoutBuilder: (currentChild, previousChildren) =>
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: <Widget>[
                          if (currentChild != null) currentChild,
                        ],
                      ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  // SATU instance MicRecordButton sepanjang gesture: swap
                  // cabang saat recording meng-unmount tombol yang di-hold
                  // → gesture putus → rekaman menggantung (hang).
                  child: voiceRecording
                      ? MicRecordButton(
                          isRecording: true,
                          isLocked: voiceLocked,
                          onTap: () => stopVoiceRecord(send: true),
                          onLongPressStart: startVoiceRecord,
                          onLongPressCancel: cancelVoiceRecord,
                          onLock: lockVoiceRecord,
                          onPickUpChanged: (v) =>
                              setState(() => voicePickUp = v),
                          size: 40,
                        )
                      : (value.text.trim().isEmpty && _decodedPhoto == null
                      ? MicRecordButton(
                          isRecording: false,
                          isLocked: voiceLocked,
                          onTap: () => stopVoiceRecord(send: true),
                          onLongPressStart: startVoiceRecord,
                          onLongPressCancel: cancelVoiceRecord,
                          onLock: lockVoiceRecord,
                          onPickUpChanged: (v) =>
                              setState(() => voicePickUp = v),
                          size: 40,
                        )
                          : GestureDetector(
                              key: const ValueKey('send'),
                              onTap: widget.onSend,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            )),
                ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: widget.showAttachRow
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                      // Wrap: bila chip banyak (4: foto/view-once/koin/hadiah)
                      // tidak muat 1 baris di layar kecil, otomatis turun baris
                      // — dulu Row sehingga overflow menimpa layar.
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ChatAttachChip(
                            icon: Icons.image_rounded,
                            color: AppTheme.primary,
                            label: s.menuSendPhoto,
                            onTap: widget.onSendPhoto,
                          ),
                          ChatAttachChip(
                            icon: Icons.timer_rounded,
                            color: Colors.orange,
                            label: s.menuViewOnce,
                            onTap: widget.onSendViewOnce,
                          ),
                          if (widget.onSendCoin != null)
                            ChatAttachChip(
                              icon: Icons.monetization_on_rounded,
                              color: const Color(0xFFFFB300),
                              label: s.menuSendCoin,
                              onTap: widget.onSendCoin!,
                            ),
                          if (widget.onOpenGiftPanel != null)
                            ChatAttachChip(
                              icon: Icons.card_giftcard,
                              color: Colors.pinkAccent,
                              label: s.menuSendGift,
                              onTap: widget.onOpenGiftPanel!,
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
