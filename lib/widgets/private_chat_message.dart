import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/gifts.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/photo_cache.dart';
import '../services/screen_secure_service.dart';
import '../services/storage_photo_service.dart';

// cacheKey untuk PhotoCache = cacheKey yang dipakai chat_service
// ('private_$chatId' untuk private chat). Dipakai private chat & admin monitor.
String cacheKeyFor(String chatId) => 'private_$chatId';

// Top-level function untuk compute() isolate — decode base64 + dimensi di background
DecodedImage? decodeImageB64(String base64) {
  try {
    final bytes = base64Decode(base64);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return DecodedImage(bytes, 0, 0);
    return DecodedImage(bytes, decoded.width, decoded.height);
  } catch (_) {
    return null;
  }
}

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const DecodedImage(this.bytes, this.width, this.height);
}

// Top-level untuk compute() — base64 → bytes (fullscreen viewer).
Uint8List? b64ToBytes(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData, bounded 80 (LRU) cegah OOM di 1M.
final decodedImageCache = <int, DecodedImage>{};
const _decodedCacheMax = 80;
void _putDecodedCache(int key, DecodedImage img) {
  if (decodedImageCache.length >= _decodedCacheMax) {
    decodedImageCache.remove(decodedImageCache.keys.first);
  }
  decodedImageCache[key] = img;
}

// Teks + waktu: 1 baris → inline [teks  waktu]; 2+ baris → waktu di baris
// baru rata kanan/kiri, sejajar dengan waktu pesan 1 baris di atasnya.
class MessageTextWithTime extends StatelessWidget {
  final String text;
  final String timeStr;
  final TextStyle textStyle;
  final TextStyle timeStyle;
  final bool alignRight;
  final Widget? trailing;
  const MessageTextWithTime({
    super.key,
    required this.text,
    required this.timeStr,
    required this.textStyle,
    required this.timeStyle,
    required this.alignRight,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.8;
        final tp = TextPainter(
          text: TextSpan(text: text, style: textStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final timeTp = TextPainter(
          text: TextSpan(text: timeStr, style: timeStyle),
          textDirection: Directionality.of(context),
        )..layout();
        final extra = timeTp.width + 8 + (trailing != null ? 16.0 : 0);
        final wraps = tp.width + extra > available;
        if (!wraps) {
          return RichText(
            text: TextSpan(
              style: textStyle,
              children: [
                TextSpan(text: text),
                const TextSpan(text: '  '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.belowBaseline,
                  baseline: TextBaseline.alphabetic,
                  child: Text(timeStr, style: timeStyle),
                ),
                if (trailing != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.belowBaseline,
                    baseline: TextBaseline.alphabetic,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: trailing,
                    ),
                  ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: alignRight
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: textStyle),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(timeStr, style: timeStyle),
                if (trailing != null) ...[const SizedBox(width: 3), trailing!],
              ],
            ),
          ],
        );
      },
    );
  }
}

class MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final String chatKey;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  // Image kosong karena di luar window auto-load (pesan lama) → tampilkan
  // icon refresh; klik memanggil onRetryImage(messageId).
  final bool isImageDeferred;
  final Future<void> Function(String messageId)? onRetryImage;
  // Admin monitor: view-once yang sudah expired tetap bisa dilihat admin.
  final bool isAdminView;
  // Room chat pakai tabel 'messages' untuk clear view-once.
  final bool isRoom;
  // Long-press untuk buka menu (Balas / Edit / Hapus) seperti WhatsApp.
  // LayerLink dipakai agar action bar (icon) bisa di-anchor tepat di atas
  // bubble dan ikut mengikuti posisi bubble saat list di-scroll.
  final void Function(LongPressStartDetails, MessageModel, LayerLink)?
  onLongPressMenu;
  // Link anchor milik bubble ini (dibuat & dikelola oleh screen agar stabil
  // antar rebuild ListView — lihat _msgLinks di private_chat_screen).
  final LayerLink link;
  const MessageBubble({
    super.key,
    required this.msg,
    required this.chatKey,
    required this.isMe,
    required this.isRead,
    this.isPending = false,
    this.isImageDeferred = false,
    this.onRetryImage,
    this.isAdminView = false,
    this.isRoom = false,
    this.onLongPressMenu,
    required this.link,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    // Pesan yang dihapus (soft delete) → tampilkan teks redup, bukan isinya.
    if (msg.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              s.messageDeleted,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    final timeStr = DateFormat.Hm().format(msg.timestamp.toLocal());
    return CompositedTransformTarget(
      link: link,
      child: GestureDetector(
        onLongPressStart: (d) => onLongPressMenu?.call(d, msg, link),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    // Bubble solid (tidak transparan) — tint primary di-blend ke bgCard.
                    // Bubble lawan (other) pakai bgCard (putih di light mode) + shadow
                    // halus supaya tetap kontras di atas wallpaper chat apa pun.
                    color: msg.type == 'coin'
                        ? Color(0xFFFFF3C4)
                        : (isMe
                              ? Color.alphaBlend(
                                  AppTheme.primary.withValues(alpha: 0.25),
                                  AppTheme.bgCard,
                                )
                              : AppTheme.bgCard),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 6,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isMe ? 14 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (msg.repliedToText != null &&
                          msg.repliedToText!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.15)
                                : AppTheme.bgScreen.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: AppTheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.repliedToSenderName ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                msg.repliedToText!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      if (msg.type == 'image' && msg.imageData.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: MessageImage(
                                imageData: msg.imageData,
                                chatKey: chatKey,
                                messageId: msg.id,
                              ),
                            ),
                            if (msg.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  msg.text,
                                  style: AppText.body.copyWith(
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    timeStr,
                                    style: AppText.micro.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 3),
                                    Icon(
                                      isPending
                                          ? Icons.done
                                          : (isRead
                                                ? Icons.done_all
                                                : Icons.done),
                                      size: 12,
                                      color: isPending
                                          ? AppTheme.textSecondary
                                          : (isRead
                                                ? AppTheme.primary
                                                : AppTheme.textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      else if (msg.type == 'image' &&
                          msg.imageData.isEmpty &&
                          isImageDeferred)
                        DeferredImage(onTap: () => onRetryImage?.call(msg.id))
                      else if (msg.type == 'view_once' ||
                          msg.type == 'view_once_expired')
                        Stack(
                          children: [
                            ViewOnceImage(
                              imageData: msg.imageData,
                              chatKey: chatKey,
                              isMe: isMe,
                              messageId: msg.id,
                              isExpired: msg.type == 'view_once_expired',
                              isAdminView: isAdminView,
                              isRoom: isRoom,
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      timeStr,
                                      style: AppText.micro.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (isMe) ...[
                                      const SizedBox(width: 3),
                                      Icon(
                                        isPending
                                            ? Icons.done
                                            : (isRead
                                                  ? Icons.done_all
                                                  : Icons.done),
                                        size: 12,
                                        color: isPending
                                            ? Colors.white70
                                            : (isRead
                                                  ? const Color(0xFF7EC8FF)
                                                  : Colors.white70),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (msg.type == 'coin')
                        Builder(
                          builder: (context) {
                            final s = context.read<LocaleProvider>().s;
                            final amount = int.tryParse(msg.text) ?? 0;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '🪙',
                                  style: TextStyle(fontSize: AppGlyph.sm),
                                ),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.coinBubbleSent(amount)
                                        : s.coinBubbleReceived(amount),
                                    style: AppText.bodyStrong.copyWith(
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'gift')
                        Builder(
                          builder: (context) {
                            final s = context.read<LocaleProvider>().s;
                            final g = giftById(msg.text);
                            final emoji = g?.emoji ?? '🎁';
                            final name = g == null
                                ? ''
                                : (s.isId ? g.nameId : g.nameEn);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  emoji,
                                  style: TextStyle(fontSize: AppGlyph.md),
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    isMe
                                        ? s.giftBubbleSent(name)
                                        : s.giftBubbleReceived(name),
                                    style: AppText.bodyStrong.copyWith(
                                      color: Color(0xFFB8860B),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  timeStr,
                                  style: AppText.micro.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else if (msg.type == 'call')
                        Builder(
                          builder: (context) {
                            final isVideoCall = msg.text.contains('📹');
                            // Hapus emoji awal (📹/📞) dari teks karena ikon sudah
                            // ditampilkan terpisah — hindari ikon ganda. Pakai
                            // replace literal (bukan regex) supaya surrogate emoji
                            // tidak rusak jadi karakter '?'.
                            final displayText = msg.text
                                .replaceFirst('📹', '')
                                .replaceFirst('📞', '')
                                .trimLeft();
                            // Warna ikon mengikuti hasil panggilan (teks status
                            // disimpan berbahasa Inggris — stabil antar locale):
                            // hijau = panggilan terhubung, merah = gagal/tak dijawab.
                            const successMarkers = ['Call ended'];
                            const failMarkers = [
                              'Missed call',
                              'Call declined',
                              'Call canceled',
                              'Busy',
                              'Call failed',
                            ];
                            final callIconColor =
                                successMarkers.any(displayText.contains)
                                ? Colors.greenAccent
                                : failMarkers.any(displayText.contains)
                                ? Colors.redAccent
                                : AppTheme.textSecondary;
                            return RichText(
                              text: TextSpan(
                                style: AppText.body.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                                children: [
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(
                                      isVideoCall ? Icons.videocam : Icons.call,
                                      size: 16,
                                      color: callIconColor,
                                    ),
                                  ),
                                  const WidgetSpan(child: SizedBox(width: 6)),
                                  TextSpan(text: displayText),
                                  const TextSpan(text: '  '),
                                  WidgetSpan(
                                    alignment:
                                        PlaceholderAlignment.belowBaseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Text(
                                      timeStr,
                                      style: AppText.micro.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      else
                        MessageTextWithTime(
                          text: msg.text,
                          timeStr: msg.edited
                              ? '$timeStr ${s.msgEdited}'
                              : timeStr,
                          textStyle: AppText.body,
                          timeStyle: AppText.micro.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                          alignRight: isMe,
                          trailing: isMe
                              ? Icon(
                                  isPending
                                      ? Icons.done
                                      : (isRead ? Icons.done_all : Icons.done),
                                  size: 12,
                                  color: isPending
                                      ? AppTheme.textSecondary
                                      : (isRead
                                            ? AppTheme.primary
                                            : AppTheme.textSecondary),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Image yang belum di-load (pesan lama di luar window 50) — tampilkan icon refresh.
class DeferredImage extends StatelessWidget {
  final VoidCallback? onTap;
  const DeferredImage({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, color: AppTheme.textSecondary, size: 22),
            SizedBox(height: 4),
            Text(
              s.msgPhotoTapToLoad,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final String messageId;
  const MessageImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.messageId,
  });

  @override
  State<MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<MessageImage> {
  DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = decodedImageCache[key];
    if (_decoded == null) _decode(key);
  }

  @override
  void didUpdateWidget(MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      final key = widget.imageData.hashCode;
      _decoded = decodedImageCache[key];
      if (_decoded == null) _decode(key);
    }
  }

  Future<void> _decode(int key) async {
    var data = widget.imageData;
    // PATH storage (belum base64) → download dulu. decodeImageB64 melempar
    // null untuk input non-base64, jadi jangan memanggilnya dengan path.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
    }
    if (data.isEmpty) return;
    final decoded = await compute(decodeImageB64, data);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Decode gagal — jangan cache null (dipaksa `!` dulu bikin crash).
      return;
    }
    _putDecodedCache(key, decoded);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return Container(
        width: 200,
        height: 200,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Text(
          s.msgPhotoExpired,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    final aspect = decoded.width / decoded.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return GestureDetector(
      onTap: () => _openFullscreen(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          decoded.bytes,
          width: width,
          height: height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            width: 200,
            height: 200,
            color: AppTheme.bgInput,
            alignment: Alignment.center,
            child: Text(
              s.msgPhotoExpired,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          bytes: decoded.bytes,
          fullLoader: () =>
              PhotoCache.instance.load(widget.chatKey, widget.messageId),
        ),
      ),
    );
  }
}

// ── View Once Image ──────────────────────────────────────────────────────────
enum ViewOnceState { idle, viewing, expired }

// Timer & state persist di luar widget lifecycle — ListView.builder recycle
// widget saat scroll, tapi timer harus terus jalan & state tidak boleh reset.
class ViewOnceTick {
  int left = 10;
  Timer? timer;
  final ValueNotifier<int> countdown = ValueNotifier<int>(10);
  ViewOnceState _state = ViewOnceState.idle;
  final ValueNotifier<ViewOnceState> stateNotifier =
      ValueNotifier<ViewOnceState>(ViewOnceState.idle);
  bool viewerOpen = false;
  DecodedImage? decoded;

  ViewOnceState get state => _state;
  set state(ViewOnceState s) {
    _state = s;
    stateNotifier.value = s;
  }

  void dispose() {
    timer?.cancel();
    countdown.dispose();
    stateNotifier.dispose();
  }
}

final viewOnceStates = <String, ViewOnceTick>{};

class ViewOnceImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final bool isMe;
  final String? messageId;
  final bool isExpired;
  // Admin monitor: lewati kartu "expired" — foto tetap bisa dilihat.
  final bool isAdminView;
  // Room chat pakai tabel 'messages', private pakai 'private_messages'.
  final bool isRoom;
  const ViewOnceImage({
    super.key,
    required this.imageData,
    required this.chatKey,
    required this.isMe,
    this.messageId,
    this.isExpired = false,
    this.isAdminView = false,
    this.isRoom = false,
  });

  @override
  State<ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<ViewOnceImage> {
  late ViewOnceTick _tick;
  DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    // Admin monitor: bypass global viewOnceStates — tidak perlu timer/expired.
    // Decode langsung dari imageData (yang sekarang selalu utuh di DB).
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty) _decodeAdmin();
      return;
    }
    final id = widget.messageId ?? 'pending-${widget.imageData.hashCode}';
    _tick = viewOnceStates[id] ?? (viewOnceStates[id] = ViewOnceTick());
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
    }
    if (_tick.state == ViewOnceState.expired) return;
    _decoded = _tick.decoded;
    if (_decoded == null) _decode();
  }

  @override
  void didUpdateWidget(ViewOnceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAdminView) {
      if (widget.imageData.isNotEmpty &&
          widget.imageData != oldWidget.imageData) {
        _decodeAdmin();
      }
      return;
    }
    if (widget.isExpired && _tick.state != ViewOnceState.viewing) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      setState(() {});
      return;
    }
    if (_tick.state == ViewOnceState.expired) return;
    if (widget.imageData != oldWidget.imageData &&
        widget.imageData.isNotEmpty) {
      _decoded = _tick.decoded;
      if (_decoded == null) _decode();
    }
  }

  Future<void> _decodeAdmin() async {
    var data = widget.imageData;
    // imageData bisa berupa PATH storage (foto baru) → download dari bucket.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
    }
    if (data.isEmpty) return;
    final decoded = await compute(decodeImageB64, data);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  void dispose() {
    // Jangan dispose _tick — timer harus terus jalan via viewOnceStates
    super.dispose();
  }

  Future<void> _decode() async {
    // View-once SUDAH expired (server tandai type='view_once_expired') —
    // WAJIB terkunci permanen, apapun isi imageData. Jangan decode/tampil.
    if (widget.isExpired) {
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (mounted) setState(() {});
      return;
    }
    // Sender/load: kalau imageData thumbnail kosong, ambil dari PhotoCache
    // (messageId) dulu — view-once yang pernah dilihat pengirim harus tetap tampil.
    var data = widget.imageData;
    if (data.isEmpty) {
      final id = widget.messageId;
      if (id != null && !id.startsWith('pending-')) {
        try {
          data = await PhotoCache.instance.load(widget.chatKey, id) ?? '';
        } catch (_) {}
      }
    }
    // Data tidak tersedia (server sudah hapus image view-once & cache kosong)
    // → tampilkan kartu terkunci, jangan spinner muter terus.
    if (data.isEmpty) {
      // Kalau BUKAN expired (pesan baru view_once), jangan langsung kunci.
      // Realtime bisa truncate base64 besar → image_data broadcast kosong.
      // Photo download async akan mengisi imageData via didUpdateWidget.
      if (!widget.isExpired) return;
      _tick.state = ViewOnceState.expired;
      ScreenSecureService.exitViewOnce();
      if (!mounted) return;
      setState(() {});
      return;
    }
    // Data bisa berupa PATH storage → download dulu sebelum decode.
    if (data.isNotEmpty && StoragePhotoService.instance.isPath(data)) {
      data = await StoragePhotoService.instance.download(data) ?? '';
      if (data.isEmpty) return;
    }
    final decoded = await compute(decodeImageB64, data);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      // Decode gagal — jangan set _tick.decoded ke null/rusak.
      return;
    }
    _tick.decoded = decoded;
    if (!mounted) return;
    setState(() => _decoded = decoded);
    // Kalau user sudah tap "Lihat" sebelum gambar siap → mulai timer sekarang
    if (_tick.state == ViewOnceState.viewing && _tick.timer == null) {
      _beginCountdown();
    }
  }

  void _startViewing() {
    if (_tick.state != ViewOnceState.idle) return;
    _tick.state = ViewOnceState.viewing;
    setState(() {});
    ScreenSecureService.enterViewOnce();
    // Mulai timer hanya kalau gambar sudah siap — kalau belum, nunggu _decode selesai
    if (_decoded != null) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    if (_tick.timer != null) return;
    _tick.left = 10;
    _tick.countdown.value = 10;
    _tick.timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _tick.left--;
      _tick.countdown.value = _tick.left;
      if (_tick.left <= 0) {
        t.cancel();
        _tick.timer = null;
        _tick.state = ViewOnceState.expired;
        ScreenSecureService.exitViewOnce();
        if (_tick.viewerOpen && mounted) Navigator.of(context).maybePop();
        if (mounted) {
          setState(() {});
          _clearFromServer();
        }
        return;
      }
      if (mounted) setState(() {});
    });
  }

  void _openViewer() {
    if (_decoded == null || _tick.state != ViewOnceState.viewing || !mounted)
      return;
    _tick.viewerOpen = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PhotoViewerScreen(
              bytes: _decoded!.bytes,
              fullLoader: () {
                final id = widget.messageId;
                if (id == null || id.startsWith('pending-'))
                  return Future.value(null);
                return PhotoCache.instance.load(widget.chatKey, id);
              },
              countdown: _tick.countdown,
            ),
          ),
        )
        .whenComplete(() => _tick.viewerOpen = false);
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await context.read<ChatProvider>().clearViewOnceImage(
        id,
        isRoom: widget.isRoom,
      );
    } catch (_) {}
  }

  Widget _buildAdminView(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final decoded = _decoded;
    final w = decoded != null ? _viewWidth(decoded) : 200.0;
    final h = decoded != null ? _viewHeight(decoded) : 200.0;
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            decoded != null
                ? Image.memory(
                    decoded.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  )
                : Container(
                    color: AppTheme.bgInput,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    ),
                  ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      s.msgViewOnce,
                      style: AppText.micro.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (decoded == null) return child;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(decoded.bytes, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdminView) return _buildAdminView(context);
    return ValueListenableBuilder<ViewOnceState>(
      valueListenable: _tick.stateNotifier,
      builder: (_, st, _) {
        final s = context.read<LocaleProvider>().s;

        // Pengirim lihat foto asli + badge
        if (widget.isMe) {
          // View-once terkunci (data sudah tidak tersedia) → kartu terkunci, bukan spinner
          if (_tick.state == ViewOnceState.expired) {
            return ViewOnceLockedCard(
              title: s.viewOnceExpired,
              hint: s.viewOnceExpiredHint,
            );
          }
          final decoded = _decoded;
          final w = decoded != null ? _viewWidth(decoded) : 200.0;
          final h = decoded != null ? _viewHeight(decoded) : 200.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.high,
                        )
                      : Container(
                          color: AppTheme.bgInput,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            s.msgViewOnce,
                            style: AppText.micro.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Penerima — idle: kartu modern "tekan untuk melihat"
        if (_tick.state == ViewOnceState.idle) {
          return GestureDetector(
            onTap: _startViewing,
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00BCD4).withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.viewOnceTitle,
                    style: AppText.bodySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.viewOnceTap,
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.btnView,
                      style: AppText.label.copyWith(
                        color: const Color(0xFF1E88E5),
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Expired — kartu terkunci (tanpa image — hemat memori & tidak load foto)
        if (_tick.state == ViewOnceState.expired) {
          return ViewOnceLockedCard(
            title: s.viewOnceExpired,
            hint: s.viewOnceExpiredHint,
          );
        }

        // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
        final decoded = _decoded;
        final vw = decoded != null ? _viewWidth(decoded) : 200.0;
        final vh = decoded != null ? _viewHeight(decoded) : 200.0;
        return GestureDetector(
          onTap: _openViewer,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: vw,
              height: vh,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  decoded != null
                      ? Image.memory(
                          decoded.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      : Container(
                          color: AppTheme.bgInput,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          ValueListenableBuilder<int>(
                            valueListenable: _tick.countdown,
                            builder: (_, v, _) => Text(
                              '${v}s',
                              style: AppText.label.copyWith(
                                color: Colors.white,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Lebar/tinggi tampilan proporsional (maks 200×280) sesuai rasio asli.
  static double _viewWidth(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return width;
  }

  static double _viewHeight(DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return height;
  }
}

// ── Photo Viewer Fullscreen ─────────────────────────────────────────────────
// Menampilkan foto fullscreen (hitam) dengan zoom + close. Bubble mengirim
// THUMBNAIL (bytes) supaya viewer langsung tampil, lalu fullLoader mengambil
// versi full-res dari PhotoCache dan menggantinya begitu siap.
// Untuk view-once, countdown diteruskan dari state pemilik sehingga timer
// terus berjalan.
class PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;
  const PhotoViewerScreen({
    super.key,
    required this.bytes,
    this.fullLoader,
    this.countdown,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  Uint8List? _fullBytes;

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

  Future<void> _loadFull() async {
    final loader = widget.fullLoader;
    if (loader == null) return;
    try {
      final b64 = await loader();
      if (b64 == null || b64.isEmpty || !mounted) return;
      final bytes = await compute(b64ToBytes, b64);
      if (bytes == null || !mounted) return;
      setState(() => _fullBytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _fullBytes ?? widget.bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            if (_fullBytes == null && widget.fullLoader != null)
              const Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Tutup',
              ),
            ),
            if (widget.countdown != null)
              Positioned(
                top: 12,
                right: 16,
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.countdown!,
                  builder: (_, secs, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${secs}s',
                          style: AppText.bodyStrong.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
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
    );
  }
}

// Kartu "foto sudah kadaluarsa" — dipakai pengirim & penerima (design sama).
class ViewOnceLockedCard extends StatelessWidget {
  final String title;
  final String hint;
  const ViewOnceLockedCard({
    super.key,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        height: 140,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF37474F), Color(0xFF263238)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_clock_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.label.copyWith(
                      color: Colors.white,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AppText.micro.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w400,
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
