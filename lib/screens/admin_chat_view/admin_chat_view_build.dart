part of '../admin_chat_view_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _AcBuildMx on _AdminBase {
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // JANGAN watch AdminProvider — notifyListeners (poll/tab lain) bikin
    // seluruh layar rebuild = kedip. Data pesan diambil via _applyMessages
    // (read), hasMore disimpan di state lokal.
    final watchingVideo = _watch != null && _watch!.isVideo;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        // titleSpacing 0: area judul mulai tepat di kanan tombol back →
        // grup (avatar-nama-avatar) benar-benar di tengah antara tombol back
        // dan tepi kanan layar (default 16dp menggeser ke kanan).
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        title: Center(
          child: Row(
            // Grup (avatar tumpang-tindih + nama) di tengah — gaya sama
            // dengan kartu di daftar monitor.
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerAvatarPair(),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.chatLabel,
                  textAlign: TextAlign.center,
                  style: AppText.titleEmphasis.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Tanpa bar loading — data dari SQLite instan (WhatsApp-style).
          if (_error)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 6),
              color: AppTheme.danger.withValues(alpha: 0.1),
              child: Text(
                s.adminChatError,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: AppTheme.danger),
              ),
            ),
          // Chip "mendengarkan" untuk call audio — masuk chat = mulai dengar,
          // keluar dari layar ini = berhenti.
          if (_watch != null && !_watch!.isVideo)
            AudioListenChip(session: _watch!),
          Expanded(
            child: Stack(
              children: [
                _msgs.isEmpty && _firstResolved
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: AppTheme.textSecondary,
                            ),
                            SizedBox(height: 12),
                            Text(
                              s.adminChatNoChats,
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetch(force: true),
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          // Bangun sedikit item di luar viewport — kartu jauh
                          // tidak ikut decode foto (buka chat banyak pesan
                          // tidak memuat puluhan gambar sekaligus).
                          scrollCacheExtent: ScrollCacheExtent.pixels(200),
                          padding: EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            MediaQuery.of(context).padding.bottom + 16,
                          ),
                          itemCount: _items.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            // Spinner footer HANYA saat load-more benar-benar
                            // berjalan (dulu selalu tampil selama _hasMore →
                            // terlihat "muter" terus tiap buka chat).
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            }
                            final item = _items[_items.length - 1 - i];
                            if (item.dateLabel != null)
                              return DateChip(label: item.dateLabel!);
                            final msg = item.msg!;
                            final isMe = msg.senderId != _leftUid;
                            // Samakan chat asli: centang-2 hanya bila
                            // PENERIMA sudah baca (timestamp < last-read
                            // penerima). Tak diketahui → centang-1.
                            final recipient = _recipientOf(msg.senderId);
                            final readAt = recipient != null
                                ? _lastRead[recipient]
                                : null;
                            final isRead =
                                readAt != null &&
                                msg.timestamp.isBefore(readAt);
                            // Foto kosong & pesan lama (> 50 dari terbaru) →
                            // deferred (ikon refresh; tap memuat). SAMA
                            // dengan chat user: tanpa batas ini, membuka chat
                            // berisi ratusan foto lama memicu ratusan
                            // RPC/unduh sekaligus. `i` = indeks dari item
                            // terbaru (list reverse), jadi i>=50 = di luar 50
                            // pesan terbaru.
                            final isImageDeferred =
                                msg.type == 'image' &&
                                msg.imageData.isEmpty &&
                                i >= 50;
                            // RepaintBoundary per bubble: scroll tidak
                            // merender ulang bubble lain (isolasi repaint) —
                            // kunci utama anti-jank saat pesan banyak.
                            // Video di luar 50 terbaru → poster tidak
                            // auto-load (hemat kuota); tap memuat.
                            return RepaintBoundary(
                              child: MessageBubble(
                                key: ValueKey(msg.id),
                                link: _linkFor(msg.id),
                                msg: msg,
                                chatKey: _chatKey,
                                autoVideoPoster: i < 50,
                                isMe: isMe,
                                isRead: isRead,
                                isAdminView: true,
                                // Admin melihat percakapan 2 orang → centang
                                // muncul di KEDUA sisi (kiri & kanan), bukan
                                // hanya milik pengirim.
                                showChecksBothSides: true,
                                isImageDeferred: isImageDeferred,
                                onRetryImage: isImageDeferred
                                    ? _retryImage
                                    : null,
                                onLongPressMenu: (d, m, _) => _copyMessage(m),
                              ),
                            );
                          },
                        ),
                      ),
                // Call video aktif → overlay setengah layar seperti private
                // chat; bisa di-expand ke fullscreen.
                if (watchingVideo)
                  Positioned.fill(
                    child: AdminCallWatchOverlay(
                      session: _watch!,
                      onExpand: _expandWatch,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
