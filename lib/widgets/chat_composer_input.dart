import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../mixins/voice_recorder_mixin.dart';
import '../providers/locale_provider.dart';
import '../utils/mention.dart';
import '../utils.dart' show dlog;
import 'chat_video_bubble.dart';
import 'mic_record_button.dart';
import 'mention_autocomplete.dart';
import 'chat_ui_shared.dart';
import 'composer_link_preview.dart';
import 'emoji_picker_sheet.dart';
import 'location_bubble.dart';

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
  /// Thumbnail base64 video yang sedang di-preview (null = tidak ada).
  final String? pendingVideoPoster;
  /// Path file video lokal (untuk tombol play di preview).
  final String? pendingVideoPath;
  /// Durasi video preview (ms) — untuk label.
  final int pendingVideoMs;
  /// Video "sekali lihat" dipilih? (toggle di preview video).
  final bool videoOnce;
  final ValueChanged<bool>? onVideoOnceChanged;
  final VoidCallback? onCancelVideo;
  /// Progress kompres video 0..1 (null = tidak sedang kompres).
  final double? videoCompressing;
  /// Chip "Kirim Video" — null bila fitur tidak aktif (room).
  final VoidCallback? onSendVideo;
  /// Status toggle HD preview (ala WhatsApp).
  final bool photoHd;
  final ValueChanged<bool>? onHdChanged;
  /// Timer view-once preview (detik; null = foto normal).
  final int? viewTimerSecs;
  /// null = sembunyikan pemilih timer (room). Non-null = private.
  final ValueChanged<int?>? onViewTimerChanged;
  final VoidCallback? onOpenGiftPanel;
  final void Function(String filePath, int durationMs)? onSendVoice;
  /// Sinyal 'sedang merekam' (private pakai typing kind=recording).
  final VoidCallback? onRecordingSignal;
  /// Sinyal 'sedang mengetik' (private/room beda saluran).
  final VoidCallback? onTyping;
  /// Kirim koin (khusus chat 1:1). null = chip tidak tampil.
  final VoidCallback? onSendCoin;
  /// Kirim lokasi (private & room). null = chip tidak tampil.
  final VoidCallback? onSendLocation;
  /// Lokasi yang sedang di-preview (di atas kolom ketik). null = tidak ada.
  final ChatLocation? pendingLocation;
  /// Batalkan preview lokasi.
  final VoidCallback? onCancelLocation;
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
    this.pendingVideoPoster,
    this.pendingVideoPath,
    this.pendingVideoMs = 0,
    this.videoOnce = false,
    this.onVideoOnceChanged,
    this.onCancelVideo,
    this.videoCompressing,
    this.onSendVideo,
    this.photoHd = false,
    this.onHdChanged,
    this.viewTimerSecs,
    this.onViewTimerChanged,
    this.onOpenGiftPanel,
    this.onSendVoice,
    this.onRecordingSignal,
    this.onTyping,
    this.onSendCoin,
    this.onSendLocation,
    this.pendingLocation,
    this.onCancelLocation,
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

  String _viewTimerLabel(dynamic s) {
    final v = widget.viewTimerSecs;
    if (v == null) return s.viewTimerOff;
    if (v <= 0) return s.viewTimerOnce;
    return s.viewTimerSecs(v);
  }

  /// Buka pemutar video untuk preview (file lokal hasil kompres).
  void _openVideoPreview() {
    final path = widget.pendingVideoPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          file: file,
          durationMs: widget.pendingVideoMs,
        ),
      ),
    );
  }

  /// Label durasi video ringkas: "0:07" / "1:05" ( maks 60 dtk → "1:00").
  static String _fmtVideoDuration(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  /// Pilihan timer view-once saat preview (private): normal / 1x / 3s / 10s.
  /// -1 = tanpa timer (sentinel supaya dismiss tidak ikut me-reset).
  Future<void> _pickViewTimer(BuildContext context) async {
    final s = context.read<LocaleProvider>().s;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.menuViewOnce, style: AppText.titleEmphasis),
              const SizedBox(height: 2),
              Text(
                s.viewTimerHint,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              for (final opt in [-1, 0, 3, 10])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    opt < 0
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    size: 20,
                    color: (opt < 0 ? null : opt) == widget.viewTimerSecs
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  title: Text(
                    opt < 0
                        ? s.viewTimerOff
                        : opt <= 0
                        ? s.viewTimerOnce
                        : s.viewTimerSecs(opt),
                  ),
                  trailing: (opt < 0 ? null : opt) == widget.viewTimerSecs
                      ? const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: AppTheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, opt),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    widget.onViewTimerChanged?.call(picked < 0 ? null : picked);
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
                      // Toggle HD ala WhatsApp (kiri atas; timer di kiri
                      // bawah). Aktif = bg primary, mati = hitam transparan.
                      if (widget.onHdChanged != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: GestureDetector(
                            onTap: () =>
                                widget.onHdChanged!(!widget.photoHd),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: widget.photoHd
                                    ? AppTheme.primary
                                    : Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                context
                                    .read<LocaleProvider>()
                                    .s
                                    .photoHdLabel,
                                style: AppText.label.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Pemilih timer view-once (private saja).
                      if (widget.onViewTimerChanged != null)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: GestureDetector(
                            onTap: () => _pickViewTimer(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _viewTimerLabel(
                                      context
                                          .read<LocaleProvider>()
                                          .s,
                                    ),
                                    style: AppText.label.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // ── Preview VIDEO (private) ──
            // Poster + badge durasi + tombol play (indikatif) + batal.
            // Progress kompres ditampilkan di sini juga supaya user tahu
            // prosesnya (video 60 dtk bisa 20-40 dtk di HP low-end).
            if (widget.pendingVideoPath != null ||
                widget.videoCompressing != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      if (widget.pendingVideoPoster != null)
                        Image.memory(
                          base64Decode(widget.pendingVideoPoster!),
                          width: double.infinity,
                          height: 150,
                          fit: BoxFit.cover,
                          cacheHeight: 450,
                          gaplessPlayback: true,
                        )
                      else
                        Container(
                          width: double.infinity,
                          height: 150,
                          color: AppTheme.bgInput,
                        ),
                      // Overlay gelap + tombol play. KETUK = buka pemutar
                      // (video hanya bisa dilihat dari file, jadi tombol ini
                      // aktif hanya bila path lokal tersedia).
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: (widget.pendingVideoPath != null &&
                                  widget.pendingVideoPath!.isNotEmpty)
                              ? () => _openVideoPreview()
                              : null,
                          child: Container(
                            color: Colors.black26,
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Kiri bawah: badge durasi + tombol "sekali lihat".
                      // (Video tidak punya pilihan timer detik — "sekali
                      // lihat" = terkunci setelah ditonton sekali.)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.pendingVideoMs > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _fmtVideoDuration(widget.pendingVideoMs),
                                  style: AppText.label.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (widget.onVideoOnceChanged != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => widget.onVideoOnceChanged!(
                                  !widget.videoOnce,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.videoOnce
                                        ? AppTheme.primary
                                        : Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.visibility_off_outlined,
                                        size: 13,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.viewTimerOnce,
                                        style: AppText.label.copyWith(
                                          color: Colors.white,
                                          fontWeight: widget.videoOnce
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Progress kompres (bawah, full width).
                      if (widget.videoCompressing != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: widget.videoCompressing,
                            minHeight: 4,
                            backgroundColor: Colors.black26,
                            valueColor: const AlwaysStoppedAnimation(
                              AppTheme.primary,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: widget.onCancelVideo,
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
            // ── Preview LOKASI (private & room) ──
            // Peta mini di atas kolom ketik (seragam dengan preview video).
            // Kirim terjadi dari tombol send — boleh tanpa/with caption.
            if (widget.pendingLocation != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      LocationBubble(
                        location: widget.pendingLocation!,
                        width: double.infinity,
                        height: 150,
                        interactive: true,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: widget.onCancelLocation,
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
                // `_ForceRebuild`: memaksa cabang mic/send dievaluasi ulang
                // saat foto/video pending berubah. `ValueListenableBuilder`
                // di bawah hanya mendengar TEKS — memilih video tak mengubah
                // teks, sehingga tombol tetap mic (tap = rekam suara, video
                // tak terkirim). InheritedWidget dengan key berubah =
                // dependents rebuild tanpa me-remount MicRecordButton
                // (gesture tahan-rekam tetap utuh).
                _ForceRebuild(
                  token: Object.hash(
                    widget.pendingVideoPath,
                    widget.pendingLocation,
                    _decodedPhoto != null,
                    voiceRecording,
                  ),
                  child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    // Dependensi eksplisit ke _ForceRebuild: pemicu rebuild
                    // saat foto/video pending berubah (tanpa ini
                    // InheritedWidget tak berpengaruh — tak ada dependant).
                    context
                        .dependOnInheritedWidgetOfExactType<_ForceRebuild>();
                    return AnimatedSwitcher(
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
                      // Ada video/lokasi pending = tombol kirim (bukan mic),
                      // supaya bisa dikirim tanpa caption.
                      : (value.text.trim().isEmpty &&
                              _decodedPhoto == null &&
                              widget.pendingVideoPath == null &&
                              widget.pendingLocation == null
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
                              onTap: () {
                                dlog('[LOC] SEND TAP pendingLoc=${widget.pendingLocation != null}');
                                widget.onSend();
                              },
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
                    );
                  },
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
                          if (widget.onSendVideo != null)
                            ChatAttachChip(
                              icon: Icons.videocam_rounded,
                              color: const Color(0xFF7E57C2),
                              label: s.menuSendVideo,
                              onTap: widget.onSendVideo!,
                            ),
                          ChatAttachChip(
                            icon: Icons.timer_rounded,
                            color: Colors.orange,
                            label: s.menuViewOnce,
                            onTap: widget.onSendViewOnce,
                          ),
                          if (widget.onSendLocation != null)
                            ChatAttachChip(
                              icon: Icons.location_on_rounded,
                              color: Colors.green,
                              label: s.menuSendLocation,
                              onTap: widget.onSendLocation!,
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

/// Memaksa subtree rebuild saat [token] berubah, TANPA mengganti identity
/// elemen anak (tidak seperti key pada widget) — sehingga gesture
/// tahan-rekam pada `MicRecordButton` tidak terputus.
///
/// Dipakai untuk area tombol mic/send yang hidup di dalam
/// `ValueListenableBuilder<TextEditingValue>` (hanya mendengar teks):
/// memilih video/foto tidak mengubah teks, jadi tanpa pemicu tambahan
/// tombol TIDAK pernah berubah dari mic → send.
class _ForceRebuild extends InheritedWidget {
  final int token;
  const _ForceRebuild({required this.token, required super.child});

  @override
  bool updateShouldNotify(_ForceRebuild oldWidget) =>
      oldWidget.token != token;
}
