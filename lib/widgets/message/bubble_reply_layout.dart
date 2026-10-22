part of '../private_chat_message.dart';

// Tata letak KUTIPAN pada bubble (dipisah dari private_chat_message.dart agar
// file utama tidak melewati batas 1000 baris — lihat scripts/check_file_size.sh).
// Perilaku TIDAK berubah: hanya pemindahan kode.



/// Tata letak isi bubble dengan KUTIPAN BALASAN (ala WhatsApp).
///
/// - [layout] false (pesan TEKS / media non-kartu / tanpa kutipan): kutipan
///   bertumpuk di ATAS isi seperti sebelumnya.
/// - [layout] true (FOTO/VIDEO/LOKASI/VIEW-ONCE berbalasan): isi dibungkus
///   Row — MEDIA (elemen pertama [children]) di KIRI dan PANEL KANAN berisi
///   kutipan + caption + jam. Caption ("teks isi") sengaja dipindah ke panel
///   kanan agar bubble tidak memanjang ke bawah (persis WhatsApp).
///
/// Elemen pertama [children] WAJIB media (kartu) saat [layout] true; sisanya
/// (caption/link/jam) masuk panel kanan.
Widget _replyPanel({
  required bool layout,
  required ReplyQuote? quote,
  required double panelWidth,
  required List<Widget> children,
}) {
  if (quote == null) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
  if (!layout) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [quote, ...children],
    );
  }
  final media = children.isNotEmpty ? children.first : const SizedBox.shrink();
  final rest = children.length > 1 ? children.sublist(1) : const <Widget>[];
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      media,
      const SizedBox(width: 6),
      ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 96,
          maxWidth: panelWidth + 6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: quote,
            ),
            ...rest,
          ],
        ),
      ),
    ],
  );
}

/// Pesan teks yang membalas: isi bubble ditata [StretchToWidestColumn]
/// (lebar = konten terlebar, kutipan dibentang selebar bubble ala WhatsApp).
/// Selain itu Column biasa (tanpa biaya layout ekstra).
Widget _replyWidth(bool stretch, Widget body) => stretch
    ? StretchToWidestColumn(
        children: body is Column ? body.children : [body],
      )
    : body;

/// Geometri tata letak media berbalasan (ala WhatsApp): media di KIRI,
/// kutipan + caption + jam di PANEL KANAN.
/// Dipakai [MessageBubble] agar perhitungan lebar tidak tersebar di build.
class ReplyMediaGeometry {
  const ReplyMediaGeometry({
    required this.panelWidth,
    required this.mediaWidth,
  });

  /// Lebar panel teks kanan (kutipan + caption + jam).
  final double panelWidth;

  /// Lebar kartu media di kiri panel.
  final double mediaWidth;

  /// Hitung dari lebar layar & ada/tidaknya caption (tanpa caption panel
  /// lebih sempit). Nilai clamp menjaga layar kecil & font besar tetap aman.
  factory ReplyMediaGeometry.of({
    required double screenW,
    required bool hasCaption,
  }) {
    final panel = (hasCaption ? 148.0 : 112.0).clamp(96.0, screenW * 0.4);
    final media = (chatMediaWidth(screenW) * 0.6).clamp(
      110.0,
      screenW * 0.9 - panel - 22,
    );
    return ReplyMediaGeometry(panelWidth: panel, mediaWidth: media);
  }
}

/// Lebar bubble efektif: media berbalasan → `null` (panel kanan menentukan);
/// media biasa 90% layar, teks 80%.
double? replyBubbleLetter({required bool mediaReplyLayout, required bool isMediaCard}) =>
    mediaReplyLayout ? null : (isMediaCard ? 0.9 : 0.8);

/// Chip JAM + centang yang dioverlay di sudut kanan-bawah kartu media
/// (foto/view-once/video). Dipakai beberapa cabang bubble → disatukan di sini
/// agar file utama ramping & gaya konsisten.
class BubbleTimeOverlay extends StatelessWidget {
  const BubbleTimeOverlay({
    super.key,
    required this.timeStr,
    required this.showChecks,
    required this.isPending,
    required this.isQueued,
    required this.isRead,
    this.queueTooltip = '',
  });

  final String timeStr;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  final String queueTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeStr, style: AppText.chatTime.copyWith(color: Colors.white)),
          if (showChecks) ...[
            const SizedBox(width: 3),
            Tooltip(
              message: queueTooltip,
              child: Icon(
                (isPending || isQueued) ? Icons.done : Icons.done_all,
                size: 12,
                color: (isRead && !isPending && !isQueued)
                    ? const Color(0xFF7EC8FF)
                    : Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kartu FOTO SEKALI-LIHAT di dalam bubble (+ overlay jam & caption).
/// Dipisah dari build MessageBubble agar file utama ramping; parameter
/// geometri diterima apa adanya sehingga perilaku tetap identik.
class ViewOnceCardContent extends StatelessWidget {
  const ViewOnceCardContent({
    super.key,
    required this.msg,
    required this.chatKey,
    required this.isMe,
    required this.isAdminView,
    required this.isRoom,
    required this.timeStr,
    required this.showChecks,
    required this.isPending,
    required this.isQueued,
    required this.isRead,
    required this.mediaMaxWidth,
    required this.showCaption,
    this.queueTooltip = '',
  });

  final MessageModel msg;
  final String chatKey;
  final bool isMe;
  final bool isAdminView;
  final bool isRoom;
  final String timeStr;
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  final double mediaMaxWidth;
  final bool showCaption;
  final String queueTooltip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            ViewOnceImage(
              imageData: msg.imageData,
              chatKey: chatKey,
              isMe: isMe,
              messageId: msg.id,
              viewSecs: msg.durationMs,
              isExpired: msg.type == 'view_once_expired',
              isAdminView: isAdminView,
              isRoom: isRoom,
              // Lebar NYATA (bukan 72% layar mentah): tinggi kartu mengikuti
              // aspek × lebar, jadi selisihnya dulu memicu RenderFlex overflow.
              mediaMaxWidth: mediaMaxWidth,
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: BubbleTimeOverlay(
                timeStr: timeStr,
                showChecks: showChecks,
                isPending: isPending,
                isQueued: isQueued,
                isRead: isRead,
                queueTooltip: queueTooltip,
              ),
            ),
          ],
        ),
        // Caption foto sekali-lihat (dulu tersimpan di DB tapi tidak dirender).
        if (showCaption)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MentionAwareText(
              msg.text,
              style: AppText.chatBody.copyWith(color: AppTheme.textPrimary),
              mentions: msg.mentions,
            ),
          ),
      ],
    );
  }
}
