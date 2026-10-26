import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show activeChatId;
import '../models/message_model.dart';
import '../utils.dart';
import '../core/app_foreground.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import 'storage_photo_service.dart';
import 'sticker_fill.dart';

export 'chat_stream_types.dart';
import 'chat_stream_types.dart';

/// Sesi stream pesan satu chat (room / private). Isi lengkap closure
/// `_cachedMessagesStream` lama dipindahkan ke sini; `ChatService` hanya
/// menjadi wrapper tipis yang membuat instance ini.
class ChatStreamSession {
  /// Jumlah foto terbaru yang di-decrypt upfront saat chat dibuka (lazy
  /// penuh). Cukup untuk mengisi viewport awal + margin scroll; foto lama
  /// di-load saat bubble-nya di-build.
  ///
  /// 12 → 6 (2026-10-18): di chat yang punya BANYAK foto (mis. ChatYuk Admin
  /// = 28 foto + 21 stiker + 18 video dalam 153 pesan), memproses 12 foto
  /// sekaligus saat buka membuat slide terasa berat. Viewport awal umumnya
  /// memuat 3-5 foto, jadi 6 sudah menutupi tanpa kerja berlebih. Foto lain
  /// tetap muncul saat di-scroll (on-demand, tidak berubah).
  static const int _lazyPhotoHeadCount = 6;

  final SupabaseClient _sb;
  final String cacheKey;
  final bool isPrivate;
  final String table;
  final String filterKey;
  final String filterVal;

  // Dependensi dari ChatService diteruskan sebagai closure (pola paling
  // sederhana) supaya session tidak bergantung balik ke ChatService.
  final bool Function(MessageModel m) _needsPhotoFill;
  final Future<void> Function(String cacheKey, MessageModel msg)
  _downloadVoiceToCache;
  final Future<void> Function(String path) _prefetchVoiceBytes;

  ChatStreamSession({
    required SupabaseClient sb,
    required this.cacheKey,
    required bool Function(MessageModel m) needsPhotoFill,
    required Future<void> Function(String cacheKey, MessageModel msg)
    downloadVoiceToCache,
    required Future<void> Function(String path) prefetchVoiceBytes,
  }) : _sb = sb,
       isPrivate = cacheKey.startsWith('private_'),
       table = cacheKey.startsWith('private_')
           ? 'private_messages'
           : 'messages',
       filterKey = cacheKey.startsWith('private_') ? 'chat_id' : 'room_id',
       filterVal = cacheKey.split('_').skip(1).join('_'),
       _needsPhotoFill = needsPhotoFill,
       _downloadVoiceToCache = downloadVoiceToCache,
       _prefetchVoiceBytes = prefetchVoiceBytes;

  // Cache cutoff delete per chat (TTL 60 dtk) — hindari query private_chats
  // berulang tiap reload. Di-invalidasi saat ada event realtime pada chat.
  static final Map<String, ({DateTime? ts, DateTime fetchedAt})>
  _hiddenCutoffCache = {};

  /// Terapkan satu payload UPDATE realtime ke list pesan.
  /// Return list BARU bila cocok, null bila perlu refetch (id tak dikenal
  /// / tanpa id). Fungsi MURNI + static supaya terkunci unit test.
  /// id DB bigint (int) vs model String — bandingkan sebagai String supaya
  /// update is_deleted/edited tidak miss lalu cuma reload.
  static List<MessageModel>? applyUpdateRecord(
    List<MessageModel> current,
    Map<String, dynamic> newRecord,
  ) {
    if (newRecord['id'] == null) return null;
    final newId = '${newRecord['id']}';
    final idx = current.indexWhere((x) => x.id == newId);
    if (idx < 0) return null;
    final updated = current[idx].copyWith(
      text: newRecord.containsKey('text')
          ? (newRecord['text'] as String? ?? current[idx].text)
          : current[idx].text,
      edited: newRecord.containsKey('edited')
          ? (newRecord['edited'] as bool? ?? false)
          : current[idx].edited,
      imageData: newRecord.containsKey('image_data')
          ? (newRecord['image_data'] as String? ?? current[idx].imageData)
          : current[idx].imageData,
      type: newRecord.containsKey('type')
          ? (newRecord['type'] as String? ?? current[idx].type)
          : current[idx].type,
      isDeleted: newRecord.containsKey('is_deleted')
          ? (newRecord['is_deleted'] as bool? ?? false)
          : current[idx].isDeleted,
    );
    return List<MessageModel>.of(current)..[idx] = updated;
  }

  /// - loadCache dan fetchServer jalan PARALEL untuk tampilan secepat mungkin.
  /// - INSERT event langsung di-append ke list tanpa refetch (0 network round-trip).
  /// - UPDATE/DELETE tetap refetch karena perlu reorder.
  /// - Poll fallback hanya jalan kalau realtime diam > 25s (event terlewat),
  ///   supaya tidak duplikasi pekerjaan realtime tiap 30 detik.
  ChatMessageStream start() {
    final controller = StreamController<List<MessageModel>>.broadcast();
    // Penanda SESI DITUTUP (dideklarasikan paling awal: dipakai guard di
    // seluruh body). Controller `broadcast` sengaja TIDAK di-close() di
    // onCancel (bisa di-subscribe ulang) → `controller.isClosed` SELALU false,
    // jadi guard berbasis isClosed saja tak pernah melindungi apa pun. Dulu
    // akibatnya: `removeChannel` di onCancel memicu status `closed` →
    // requestReconnect → ~2 dtk kemudian reload + channel BARU yang tak
    // pernah dibuang (langganan yatim, 2026-10-22). `sessionClosed` di-set di
    // onCancel (semua kerja async + tulis cache berhenti) dan di-reset di
    // onListen saat sesi dipakai ulang (channel & timer dihidupkan lagi).
    var sessionClosed = false;
    bool _isDead() => sessionClosed || controller.isClosed;
    var _current = <MessageModel>[];
    var _loadingOlder = false;
    var _hasMore = true;
    final _loadMoreReqs = <Completer<void>>[];

    // Batas pesan yang ditahan di memori per chat. Tanpa ini `_current` tumbuh
    // tak terbatas → tiap emit `controller.add(...)` menyalin list makin
    // besar + ListView makin panjang → "ngelag makin lama dipakai".
    // DUA batas (2026-10-22, bug "loadOlder dibuang trim"):
    // - `_maxMessages` (100) = jendela TERBARU — dipakai selama user belum
    //   scroll mundur, dan yang disimpan ke cache lokal (cache tetap kecil).
    // - `maxHistory` (1100) = batas KERAS riwayat di memori setelah
    //   loadOlder (= jendela + 10 halaman, sama dengan loop jump-to-reply
    //   room). Dulu loadOlder menambah 100 pesan lama lalu `_trim()` ke 100
    //   terbaru → yang baru dimuat LANGSUNG dibuang → scroll mentok & lompat
    //   ke balasan lama tak pernah sampai.
    // `windowCap` = batas aktif: naik saat loadOlder (maks `maxHistory`);
    // trim hanya memangkas ujung LAMA saat pesan baru masuk / reload.
    const _maxMessages = 100;
    const maxHistory = 1100;
    var windowCap = _maxMessages;
    // Kursor paginasi TERPISAH dari `_current.first`: trim memangkas pesan
    // terlama dari `_current`, tapi kursor harus tetap menunjuk ke pesan
    // TERLAMA yang pernah dimuat sesi ini — kalau pakai `_current.first`
    // (yang sudah kepangkas), `before` mundur → fetch duplikat → `_hasMore`
    // mati palsu → history >300 tak bisa di-scroll (regresi trim).
    DateTime? _oldestFetchedTs;
    void _trim() {
      if (_current.length <= windowCap) return;
      // Buang dari DEPAN (terlama) — pertahankan pesan terbaru + posisi
      // scroll di bawah. Karena dipangkas dari atas, `_hasMore` dibiarkan
      // (masih ada yang lebih lama di server).
      _current = _current.sublist(_current.length - windowCap);
    }

    // Yang ditulis ke cache lokal: HANYA jendela terbaru (riwayat hasil
    // loadOlder tak ikut) — tulis cache tetap murah & isi cache bounded.
    List<MessageModel> cacheWindow() => _current.length <= _maxMessages
        ? _current
        : _current.sublist(_current.length - _maxMessages);

    // A1 (2026-10-11): REVISI isi — naik tiap kali isi pesan berubah.
    // `controller.add` di bawah SELALU lewat `_emit()` yang menaikkan ini.
    // Dipakai UI (`_deriveItems`) sebagai kunci cache STABIL: dulu cache
    // pakai `identical(list)` → stream emit list BARU tiap event → selalu
    // miss → O(N) recompute tiap emit (makin banyak pesan = makin lag).
    // Dengan revisi: derive HANYA saat isi benar-benar berubah.
    final revision = ValueNotifier<int>(0);
    void _emit() {
      if (_isDead()) return;
      revision.value = revision.value + 1;
      controller.add(List.unmodifiable(_current));
    }

    // Private chat: cutoff waktu delete — pesan lama (<= cutoff) tidak
    // pernah ditampilkan lagi untuk user yang menghapus, meski ada di server.
    DateTime? _hiddenCutoff;

    // Kapan terakhir realtime "hidup" — poll skip kalau masih fresh.
    DateTime lastRealtime = DateTime.now();

    // Cache write di-debounce (2s) + skip kalau data tidak berubah,
    // supaya tidak encrypt & tulis SharedPreferences tiap pesan / tiap poll.
    Timer? saveDebounce;
    String? lastSavedSig;

    void scheduleCacheSave() {
      if (_isDead() || _current.isEmpty) return;
      saveDebounce?.cancel();
      saveDebounce = Timer(const Duration(seconds: 2), () async {
        if (_isDead()) return;
        final win = cacheWindow();
        final sig = messageCacheSignature(win);
        if (sig == lastSavedSig) return;
        lastSavedSig = sig;
        try {
          await MessageCache.instance.saveMessages(cacheKey, win);
        } catch (e) {
          dlog('[ChatService] clearViewOnceImage ignored: $e');
        }
      });
    }

    // Kolom tanpa image_data — foto diambil terpisah (PhotoCache / download
    // lazy) supaya buka chat tetap cepat walau ada ratusan foto.
    // PENTING: kolom payload FITUR wajib ada di sini — kalau tidak, pesan dari
    // server/cache kehilangan definisinya → kartu (poll/kontak) hilang setelah
    // keluar-masuk chat. `contact` = payload kirim kontak; `poll` = poll room
    // (roomCols sempat belum memuat poll).
    const privateCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at,edited,is_deleted,image_path,voice_path,duration_ms,is_forwarded,mentions,video_poster,album_id,poll,contact';
    const roomCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at,edited,is_deleted,image_path,voice_path,duration_ms,replied_to_id,replied_to_text,replied_to_sender_name,is_forwarded,mentions,video_poster,album_id,poll,contact';
    // `replied_to_meta` = metadata kutipan balasan (jenis media + dimensi +
    // path video) → thumbnail di kutipan ala WhatsApp. Kolom nullable;
    // baris lama mengembalikan null (aman).
    const replyCols =
        'replied_to_id,replied_to_text,replied_to_sender_name,replied_to_meta';
    // Room: roomCols sudah memuat 3 kolom reply teks (tanpa meta) → cukup
    // tambah `replied_to_meta`. Dulu room TIDAK mengambilnya, akibatnya
    // thumbnail kutipan media hilang setiap keluar-masuk room (paritas
    // private: `privateCols` + `replyCols`).
    final cols = isPrivate
        ? '$privateCols,$replyCols'
        : '$roomCols,replied_to_meta';

    // Sync foto otomatis: server → file lokal terenkripsi. Download lazy
    // (paralel) hanya untuk pesan yang fotonya belum ada di lokal.
    final photoQueue = <MessageModel>[];
    var downloading = 0;
    const maxConcurrentPhotos = 5;

    // Batasi load foto lokal paralel — 100 foto decrypt sekaligus bikin
    // buka chat lambat. Max 4 parallel, sisanya antri.
    final _photoLoadGate = ChatSemaphore(4);

    Future<void> _drainPhotoQueue() async {
      while (photoQueue.isNotEmpty && downloading < maxConcurrentPhotos) {
        // Batch 20 foto per query — hindari N+1 select per pesan.
        // Ambil + HAPUS dari queue supaya loop bisa berhenti (take() saja
        // tidak menghapus → loop tak berujung mem-query foto yang sama).
        final batch = photoQueue.take(20).toList();
        photoQueue.removeRange(0, batch.length);
        downloading++;
        try {
          final ids = batch.map((m) => m.id).toList();
          final rows = await _sb
              .from(table)
              .select('id,image_data,image_path')
              .inFilter('id', ids);
          final byId = {
            for (final r in rows)
              '${r['id']}': (r['image_data'] as String? ?? '').isNotEmpty
                  ? (r['image_data'] as String? ?? '')
                  : (r['image_path'] as String? ?? ''),
          };
          // Download path storage dibatasi paralelnya (4) supaya tidak
          // membuka banyak koneksi sekaligus.
          for (var i = 0; i < batch.length; i += 4) {
            if (_isDead()) return;
            final chunk = batch.skip(i).take(4).toList();
            // Id pesan yang full-res-nya sudah di PhotoCache (prefetch list /
            // buka sebelumnya) — lewati download + tulis ulang di bawah.
            final cacheHitIds = <String>{};
            final results = await Future.wait(
              chunk.map((m) async {
                var data = byId[m.id] ?? '';
                if (data.isNotEmpty &&
                    StoragePhotoService.instance.isPath(data)) {
                  final mem = await PhotoCache.instance.load(cacheKey, m.id);
                  if (mem != null && mem.isNotEmpty) {
                    cacheHitIds.add(m.id);
                    return mem;
                  }
                  data =
                      await StoragePhotoService.instance.download(data) ?? '';
                }
                return data;
              }),
            );
            for (var j = 0; j < chunk.length; j++) {
              final m = chunk[j];
              final data = results[j];
              dlog(
                '[PHOTO-DBG] drain ${m.id} srcLen=${(byId[m.id] ?? '').length} dlLen=${data.length}',
              );
              if (data.isEmpty) continue;
              if (_isDead()) return;
              // save() menyimpan full-res + membuat thumbnail (dikembalikan).
              // Bubble pakai thumbnail supaya decode cepat; full-res di PhotoCache.
              // Cache-hit (prefetch) → full+thumb sudah di disk: ambil thumb
              // saja, jangan tulis ulang + compute ulang.
              final thumb = cacheHitIds.contains(m.id)
                  ? await PhotoCache.instance.loadThumb(cacheKey, m.id)
                  : await PhotoCache.instance.save(cacheKey, m.id, data);
              if (_isDead()) return;
              final idx = _current.indexWhere((x) => x.id == m.id);
              if (idx >= 0 && _needsPhotoFill(_current[idx])) {
                _current[idx] = _current[idx].copyWith(
                  imageData: thumb ?? data,
                );
                _emit();
                scheduleCacheSave();
              }
            }
          }
        } catch (e) {
          dlog(
            '[photo download] ${batch.map((m) => m.id).join(',')} error: $e',
          );
        } finally {
          downloading--;
        }
      }
    }

    void queuePhotoDownload(MessageModel m) {
      if (photoQueue.any((q) => q.id == m.id)) return;
      photoQueue.add(m);
      _drainPhotoQueue();
    }

    // Isi imageData dari file lokal (batch decrypt 1 isolate per chunk).
    // Background (tidak di-await) supaya teks tampil dulu, foto nyusul.
    // Chunk kecil → foto pertama muncul cepat, sisanya menyusul berurutan.
    // DEDUPE (cold-start ringan 2026-10-13): loadPhotosAsync dipanggil 3×
    // saat boot (memori → SQLite → server). Tanpa guard, batch head 12 foto
    // di-decrypt & di-queue 3× → I/O + emit berlebih. Kunci = id batch head
    // yang sudah pernah diproses; konten yang sama → skip.
    String? _lastPhotoHeadKey;
    // Batch foto pertama per sesi ditunda sedikit (lihat _lazyPhotoHeadCount).
    bool _firstPhotoBatchDone = false;

    void loadPhotosAsync(List<MessageModel> models) {
      if (models.isEmpty) return;
      // Voice: prefetch audio TERBARU di background (lazy) supaya tap play
      // langsung dari disk. Dibatasi 10 terbaru agar hemat kuota; voice lama
      // tetap on-demand saat di-tap (dengan spinner di bubble).
      final voices =
          models
              .where(
                (m) =>
                    m.type == 'voice' &&
                    m.imageData.isNotEmpty &&
                    StoragePhotoService.instance.isVoicePath(m.imageData),
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (voices.isNotEmpty) {
        unawaited(() async {
          for (final m in voices.take(10)) {
            if (_isDead()) return;
            await _prefetchVoiceBytes(m.imageData);
          }
        }());
      }
      final photos = models.where((m) {
        return m.type == 'image' ||
            m.type == 'view_once' ||
            m.type == 'view_once_expired';
      }).toList();
      // STIKER: path cuma di `image_data` (tak ikut cols) → isi batch.
      // Tanpa ini bubble kosong usai reload ("muncul lalu ilang").
      final stickers = [
        for (final m in models)
          if (m.type == 'sticker' && m.imageData.isEmpty) m,
      ];
      if (stickers.isNotEmpty) {
        unawaited(
          fillStickerPaths(
            sb: _sb,
            table: table,
            stickers: stickers,
            currentGetter: () => _current,
            isClosed: () => _isDead(),
            emit: _emit,
            scheduleCacheSave: scheduleCacheSave,
          ),
        );
      }
      if (photos.isEmpty) return;
      // LAZY PENUH: hanya decrypt upfront untuk foto terbaru yang terlihat
      // saat chat dibuka. Sisanya di-load on-demand saat bubble-nya di-build
      // (MessageImage._decode: thumb disk → download). Dulu SEMUA foto
      // di-decrypt saat buka chat → buka chat berisi ratusan foto terasa
      // berat (ratusan baca file + decrypt + rebuild list per pesan).
      final head = photos.take(_lazyPhotoHeadCount).toList();
      // Dedupe: id head identik dengan batch terakhir yang sudah diproses →
      // tak perlu decrypt/queue ulang (boot mem→cache→server 3×).
      final headKey = head.map((m) => m.id).join(',');
      if (headKey == _lastPhotoHeadKey) return;
      _lastPhotoHeadKey = headKey;
      // TUNDA batch foto PERTAMA (2026-10-18): decrypt + generate thumbnail
      // berjalan di ROOT ISOLATE (ui.instantiateImageCodec) sehingga berebut
      // CPU dengan frame animasi slide. Defer ~280ms (di atas durasi slide
      // 250ms) supaya buka chat mulus; foto tetap muncul (placeholder sudah
      // tampil lebih dulu dari header gambar). Batch berikutnya tidak ditunda.
      final defer = !_firstPhotoBatchDone;
      _firstPhotoBatchDone = true;
      _photoLoadGate.run(() async {
        if (defer) {
          await Future<void>.delayed(const Duration(milliseconds: 280));
          if (_isDead()) return;
        }
        if (_isDead()) return;
        final chunk = head.map((m) => m.id).toList();
        final map = await PhotoCache.instance.loadMany(cacheKey, chunk);
        if (_isDead()) return;
        // ZERO-JANK: SATU emit setelah batch (dulu _emit per foto → s.d. 12
        // rebuild ListView berurutan saat foto head tiba bersamaan).
        var changed = false;
        for (final m in head) {
          final data = map[m.id];
          if (data == null || data.isEmpty) {
            queuePhotoDownload(m);
            continue;
          }
          final idx = _current.indexWhere((x) => x.id == m.id);
          if (idx >= 0 && _needsPhotoFill(_current[idx])) {
            _current[idx] = _current[idx].copyWith(imageData: data);
            changed = true;
          }
        }
        if (changed) {
          _emit();
          scheduleCacheSave();
        }
      });
    }

    Future<List<MessageModel>> fetchServer({
      DateTime? before,
      int limit = 100,
    }) async {
      var query = _sb
          .from(table)
          .select(cols)
          .eq(filterKey, filterVal)
          .order('created_at', ascending: false)
          .limit(limit);
      if (before != null) {
        // Query pesan dengan timestamp < before (lebih lama), pakai lt().
        query = _sb
            .from(table)
            .select(cols)
            .eq(filterKey, filterVal)
            .lt('created_at', before.toUtc().toIso8601String())
            .order('created_at', ascending: false)
            .limit(limit);
      }
      final rows = await query;
      final list = rows
          .map((row) => MessageModel.fromMap('${row['id']}', snakeToCamel(row)))
          .toList();
      for (final m in list) {
        if (m.type == 'image' || m.type == 'view_once' || m.type == 'voice') {
          dlog(
            '[PHOTO-DBG] fetchServer ${m.id} type=${m.type} imgLen=${m.imageData.length} head=${m.imageData.isEmpty ? '' : m.imageData.substring(0, m.imageData.length > 30 ? 30 : m.imageData.length)}',
          );
        }
      }
      return list;
    }

    // Ambil cutoff delete user ini (UTC → local). null = tidak pernah delete.
    Future<DateTime?> fetchHiddenCutoff() async {
      if (!isPrivate) return null;
      final cached = _hiddenCutoffCache[filterVal];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt).inSeconds < 60) {
        return cached.ts;
      }
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return null;
      try {
        final row = await _sb
            .from('private_chats')
            .select('hidden_at')
            .eq('chat_id', filterVal)
            .maybeSingle();
        DateTime? ts;
        if (row != null) {
          final map = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
          final v = map[uid];
          if (v != null) ts = DateTime.tryParse('$v')?.toLocal();
        }
        _hiddenCutoffCache[filterVal] = (ts: ts, fetchedAt: DateTime.now());
        // Cap: tiap chat yang pernah dibuka menyisipkan 1 entry yang tidak
        // pernah dihapus (kecuali ada event realtime) → bounded FIFO.
        while (_hiddenCutoffCache.length > 200) {
          _hiddenCutoffCache.remove(_hiddenCutoffCache.keys.first);
        }
        return ts;
      } catch (_) {
        return null;
      }
    }

    // Guard re-entry: reload() dipanggil dari banyak sumber konkuren
    // (poll timer, INSERT error, UPDATE/DELETE realtime). Tanpa flag ini,
    // burst event memicu N fetch paralel yang saling menimpa _current
    // (race duplicate-insert / reorder). Cukup satu reload berjalan;
    // permintaan berikutnya di-coalesce lewat _reloadQueued.
    var _reloading = false;
    var _reloadQueued = false;
    Timer? reloadDebounce;

    Future<void> reload() async {
      if (_isDead()) return;
      if (_reloading) {
        _reloadQueued = true;
        return;
      }
      _reloading = true;
      try {
        // ── FRAME PERTAMA INSTAN: emit SINKRON dari memori (tanpa await) ──
        // Bila chat sudah di cache memori (dari kunjungan sebelumnya / hasil
        // prefetch saat tap di list), emit langsung → TIDAK ada "loading
        // pesan". Kalau kosong (cold start), lanjut ke muat SQLite.
        if (_current.isEmpty) {
          final mem = MessageCache.instance.peekMessages(cacheKey);
          if (mem != null && mem.isNotEmpty && !_isDead()) {
            _current = mem;
            _emit();
            loadPhotosAsync(mem);
          }
        }

        // Emit cache lokal (SQLite) tanpa tunggu cutoff network — frame
        // pertama tetap cepat bila memori miss. Cutoff & server menyusul.
        // ZERO-JANK: server fetch jalan PARALEL dengan cutoff (dulu serial:
        // cutoff di-await dulu → +1 round-trip sebelum 100 pesan diambil).
        // Filter cutoff diterapkan setelah keduanya tiba (di bawah).
        final cutoffF = fetchHiddenCutoff();
        final serverF = fetchServer(limit: 100);
        final swServer = Stopwatch()..start();
        final cacheF = _current.isEmpty
            ? MessageCache.instance.loadMessages(cacheKey)
            : Future<List<MessageModel>>.value(const <MessageModel>[]);
        final cached = await cacheF;
        if (cached.isNotEmpty && !_isDead()) {
          _current = cached;
          _emit();
          loadPhotosAsync(cached);
        }
        _hiddenCutoff = await cutoffF;
        if (_isDead()) return;
        if (_hiddenCutoff != null && _current.isNotEmpty) {
          final filtered = _current
              .where((m) => m.timestamp.isAfter(_hiddenCutoff!))
              .toList();
          if (filtered.length != _current.length) {
            _current = filtered;
            _emit();
          }
        }
        final server = await serverF;
        dlog(
          '[CACHE-TIME] $cacheKey server=${swServer.elapsedMilliseconds}ms n=${server.length}',
        );
        if (_isDead()) return;
        if (_hiddenCutoff != null) {
          server.removeWhere((m) => !m.timestamp.isAfter(_hiddenCutoff!));
        }
        // MERGE: server DESC → ASC. _current yang belum ada di server
        // disisipkan kronologis (bukan selalu di akhir) — realtime bisa
        // datang tidak urut & cache bisa berisi pesan lama di luar window
        // fetch 100 terbaru.
        // ANTI-KEDIP: cols tak memuat `image_data` → baris server stiker
        // selalu kosong; pertahankan imageData lama (lihat sticker_fill).
        final merged = preserveStickerPaths(server.reversed.toList(), _current);
        final seenIds = merged.map((m) => m.id).toSet();
        for (final m in _current) {
          if (seenIds.add(m.id)) {
            var idx = merged.length;
            for (var i = merged.length - 1; i >= 0; i--) {
              if (merged[i].timestamp.isAfter(m.timestamp)) {
                idx = i;
              } else {
                break;
              }
            }
            merged.insert(idx, m);
          }
        }
        if (_hiddenCutoff != null) {
          merged.removeWhere((m) => !m.timestamp.isAfter(_hiddenCutoff!));
        }
        _current = merged;
        _trim();
        if (_current.isNotEmpty) {
          final first = _current.first.timestamp;
          _oldestFetchedTs =
              _oldestFetchedTs == null || first.isBefore(_oldestFetchedTs!)
              ? first
              : _oldestFetchedTs;
        }
        _emit();
        scheduleCacheSave();
        // Foto di-load background — teks tidak menunggu decrypt foto.
        loadPhotosAsync(_current);
      } catch (e) {
        dlog('[_cachedMessagesStream] fetch error: $e');
        // Fallback: tampilkan cache hanya kalau server gagal.
        // Filter hiddenCutoff TETAP diterapkan — cache lokal bisa berisi
        // history sebelum delete yang tidak boleh muncul lagi.
        MessageCache.instance.loadMessages(cacheKey).then((cached) {
          if (cached.isNotEmpty && !_isDead() && _current.isEmpty) {
            var list = cached;
            if (_hiddenCutoff != null) {
              list = list
                  .where((m) => m.timestamp.isAfter(_hiddenCutoff!))
                  .toList();
            }
            if (list.isEmpty) return;
            _current = list;
            _emit();
            loadPhotosAsync(list);
          }
        });
      } finally {
        _reloading = false;
        // Ada permintaan reload yang datang saat proses berjalan → jalankan
        // sekali lagi supaya tidak ada event yang hilang.
        if (_reloadQueued && !_isDead()) {
          _reloadQueued = false;
          reload();
        }
      }
    }

    // Jadwalkan reload ter-debounce (500ms) — dipakai untuk UPDATE/DELETE/
    // fallback realtime supaya burst event tidak memicu reload beruntun.
    void scheduleReload() {
      reloadDebounce?.cancel();
      reloadDebounce = Timer(const Duration(milliseconds: 500), () {
        reload();
      });
    }

    // Nama deterministik + filter server-side (dulu hashCode tak stabil +
    // semua client terima semua insert lalu buang di client).
    // PENTING: topik STABIL tanpa sufiks percobaan — broadcast `view_once_seen`
    // dari lawan bicara ditujukan ke topik ini (`viewOnceSeenTopic`), jadi
    // sufiks `-<n>` membuatnya tidak pernah cocok. Reconnect tetap aman:
    // channel lama di-`removeChannel` SEBELUM channel baru dibuat.
    final channelName = chatStreamTopic(cacheKey);
    // null = tak ada channel aktif (sedang dibuang / sesi ditutup). WAJIB
    // di-null-kan SEBELUM `removeChannel`: status `closed` yang dipicunya
    // lalu gagal lolos guard `identical(ch, channel)` → tak memicu reconnect.
    RealtimeChannel? channel;
    // Forward-declare: attach() memicu reconnect lewat ini, tapi definisi
    // `_scheduleChannelReconnect` ada SETELAH attach (butuh `openChannel`
    // yang butuh `attach` — sirkular, tak bisa urut linear).
    late void Function() requestReconnect;
    var _reconnectAttempt = 0;
    // Status langganan kanal saat ini — dipakai hook RESUME (lihat di bawah).
    var _subscribedNow = false;

    /// Pasang SELURUH handler realtime ke [ch]. Dipanggil untuk channel awal &
    /// tiap channel BARU saat reconnect (Supabase melarang `subscribe` 2x pada
    /// instance yang sama — bug terukur "tried to subscribe multiple times").
    /// Masukkan satu pesan BARU (sumber tepercaya: payload postgres INSERT
    /// yang sudah lewat RLS, atau baris hasil fetch by id) ke list sesi.
    void ingestIncoming(MessageModel msg) {
      if (_current.any((m) => m.id == msg.id)) return; // dedupe
      if (_hiddenCutoff != null && !msg.timestamp.isAfter(_hiddenCutoff!)) {
        return;
      }
      // PENTING (perf): JANGAN `await` unduh/thumbnail di jalur realtime —
      // dulu pesan foto menunggu unduh full-res selesai SEBELUM ditampilkan
      // (dan event berikutnya ikut ngantre), jadi pesan masuk terasa
      // "lambat banget". Sekarang pesan DI-EMIT DULU (placeholder
      // spinner), lalu foto diisi di latar oleh queuePhotoDownload —
      // persis pola video (poster diurus ChatVideoBubble).
      // VOICE: unduh audio di latar (tanpa thumbnail).
      final needsPhotoFill =
          (msg.type == 'image' ||
              msg.type == 'view_once' ||
              msg.type == 'view_once_expired') &&
          msg.imageData.isNotEmpty &&
          _needsPhotoFill(msg);
      if (needsPhotoFill) {
        queuePhotoDownload(msg);
      } else if (msg.type == 'voice' && msg.imageData.isNotEmpty) {
        unawaited(_downloadVoiceToCache(cacheKey, msg));
      }
      // Sisipkan di posisi kronologis yang benar (ascending by timestamp),
      // bukan selalu di akhir — pesan realtime bisa tiba tidak urut
      // (mis. pesan riwayat call datang SETELAH user kirim chat baru).
      // In-place insert (dulu spread-copy seluruh list per pesan = O(N²)
      // saat burst).
      var insertAt = _current.length;
      for (var i = _current.length - 1; i >= 0; i--) {
        if (_current[i].timestamp.isAfter(msg.timestamp)) {
          insertAt = i;
        } else {
          break;
        }
      }
      if (insertAt >= _current.length) {
        _current.add(msg);
      } else {
        _current.insert(insertAt, msg);
      }
      _trim();
      lastRealtime = DateTime.now();
      dlog(
        '[DEBUG-READ] realtime INSERT table=$table msg=${msg.id} filter=$filterVal',
      );
      if (msg.type == 'image' ||
          msg.type == 'view_once' ||
          msg.type == 'view_once_expired' ||
          msg.type == 'video' ||
          msg.type == 'video_once' ||
          msg.type == 'video_once_expired') {
        dlog(
          '[PHOTO-DBG] rt-insert ${msg.id} type=${msg.type} imgLen=${msg.imageData.length} head=${msg.imageData.isEmpty ? '' : msg.imageData.substring(0, msg.imageData.length > 30 ? 30 : msg.imageData.length)}',
        );
      }
      _emit();
      scheduleCacheSave();
    }

    /// Broadcast `new_message` = SINYAL saja (REVIEW_2026-10-24 SEC-01):
    /// channel broadcast publik bisa dikirimi siapa pun yang tahu topiknya,
    /// jadi isi payload TIDAK dipercaya. Ambil baris aslinya by id lewat
    /// PostgREST (tunduk RLS peserta) — pesan palsu tak punya baris → diabaikan.
    Future<void> ingestBroadcastSignal(Map<String, dynamic> data) async {
      final id = data['id']?.toString() ?? '';
      if (id.isEmpty) {
        // Klien lama mengirim payload tanpa id → anggap sinyal "ada pesan".
        scheduleReload();
        return;
      }
      if (_current.any((m) => m.id == id)) return;
      final row = await _sb
          .from(table)
          .select(cols)
          .eq('id', id)
          .eq(filterKey, filterVal)
          .maybeSingle();
      if (row == null || _isDead()) return;
      ingestIncoming(MessageModel.fromMap('${row['id']}', snakeToCamel(row)));
    }

    /// Pasang SELURUH handler realtime ke [ch]. Dipanggil untuk channel awal &
    /// tiap channel BARU saat reconnect (Supabase melarang `subscribe` 2x pada
    /// instance yang sama — bug terukur "tried to subscribe multiple times").
    void attach(RealtimeChannel ch) {
      // INSERT: append langsung dari payload — tidak perlu round-trip ke server
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterKey,
          value: filterVal,
        ),
        callback: (payload) {
          _hiddenCutoffCache.remove(filterVal);
          if (_isDead()) return;
          try {
            final row = payload.newRecord;
            if (row[filterKey]?.toString() != filterVal) return;
            ingestIncoming(
              MessageModel.fromMap('${row['id']}', snakeToCamel(row)),
            );
          } catch (_) {
            scheduleReload();
          }
        },
      );
      // UPDATE: parse payload untuk update partial (jangan refetch full)
      // Filter WAJIB sama dengan INSERT/DELETE: tanpa filter, realtime UPDATE
      // bisa tidak terkirim untuk baris ini (gejala: view-once tidak berubah
      // jadi "kadaluarsa" di pengirim sampai chat dibuka ulang).
      ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterKey,
          value: filterVal,
        ),
        callback: (payload) {
          _hiddenCutoffCache.remove(filterVal);
          if (_isDead()) return;
          lastRealtime = DateTime.now();
          try {
            dlog(
              '[RT-UPDATE] $filterVal id=${payload.newRecord['id']} '
              'type=${payload.newRecord['type']}',
            );
            final next = ChatStreamSession.applyUpdateRecord(
              _current,
              payload.newRecord,
            );
            if (next == null) {
              scheduleReload();
              return;
            }
            _current = next;
            _emit();
            scheduleCacheSave();
          } catch (_) {
            scheduleReload();
          }
        },
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterKey,
          value: filterVal,
        ),
        callback: (_) {
          _hiddenCutoffCache.remove(filterVal);
          if (_isDead()) return;
          lastRealtime = DateTime.now();
          scheduleReload();
        },
      );
      // `new_message` = event klien LAMA (payload berisi isi pesan, tak
      // dipercaya) → hanya dipakai sebagai sinyal; `new_message_id` = baru.
      for (final ev in const ['new_message', chatNewMessageSignalEvent]) {
        ch.onBroadcast(
          event: ev,
          callback: (payload, [ref]) async {
            _hiddenCutoffCache.remove(filterVal);
            lastRealtime = DateTime.now();
            if (_isDead()) return;
            try {
              if (payload['chat_id']?.toString() != filterVal &&
                  payload['room_id']?.toString() != filterVal) {
                return;
              }
              await ingestBroadcastSignal(payload);
            } catch (e) {
              dlog('[Chat] broadcast $ev gagal diproses: $e');
            }
          },
        );
      }

      // PENANDA "SUDAH DILIHAT" (realtime): penerima mengirim broadcast
      // `view_once_seen` (topik dari `viewOnceSeenTopic` — SAMA dengan kanal
      // ini) setelah membuka foto sekali-lihat → pengirim langsung mengunci
      // kartunya (tanpa menunggu refetch/event UPDATE postgres yang bisa telat
      // di MIUI/Doze).
      ch.onBroadcast(
        event: 'view_once_seen',
        callback: (payload, [ref]) {
          if (_isDead()) return;
          try {
            final mid = payload['message_id']?.toString() ?? '';
            final newType = payload['type']?.toString() ?? 'view_once_expired';
            dlog('[VO-SEEN] recv id=$mid type=$newType filter=$filterVal');
            if (mid.isEmpty) return;
            final idx = _current.indexWhere((m) => m.id == mid);
            if (idx < 0) return;
            if (_current[idx].type == newType) return;
            _current = List<MessageModel>.of(_current)
              ..[idx] = _current[idx].copyWith(type: newType);
            _emit();
            scheduleCacheSave();
          } catch (e) { dlog('[RT]: $e'); }
        },
      );

      ch.subscribe((status, err) {
        // ABAIKAN callback dari kanal yang SUDAH DIGANTI (di-teardown sengaja
        // oleh reconnect/resume). removeChannel memicu status `closed` di
        // instance lama — tanpa guard ini tiap reconnect menjadwalkan
        // reconnect berikutnya → loop buat-buang kanal tiap ~2 dtk.
        // Sesi DITUTUP → abaikan semua status (termasuk `closed` dari
        // removeChannel di onCancel) supaya tak ada reconnect/channel yatim.
        if (_isDead() || !identical(ch, channel)) return;
        if (err != null) dlog('[ChatStream] realtime error: $err');
        // REALTIME RESILIENT: channel mati (mis. 1002 saat network blip) →
        // reconnect via channel BARU (bukan subscribe ulang instance).
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _subscribedNow = false;
          requestReconnect();
        } else if (status == RealtimeSubscribeStatus.subscribed) {
          _reconnectAttempt = 0; // sukses → reset backoff
          _subscribedNow = true;
          lastRealtime = DateTime.now();
          dlog('[ChatStream] subscribed topic=$channelName');
        }
      });
    } // attach: handler + subscribe terpasang ke ch.

    void openChannel() {
      _subscribedNow = false;
      final ch = _sb.channel(channelName);
      channel = ch;
      attach(ch);
    }

    // Lepas channel aktif: null-kan DULU (lihat komentar `channel`), baru
    // removeChannel.
    Future<void> dropChannel() async {
      final old = channel;
      channel = null;
      _subscribedNow = false;
      if (old == null) return;
      try {
        await _sb.removeChannel(old);
      } catch (_) {} // cleanup best-effort
    }

    openChannel();

    // State reconnect realtime (backoff). Lihat _scheduleChannelReconnect.
    final _rng = Random();
    final _reconnectDelays = const [2, 4, 8, 16, 32, 60];
    Timer? _reconnectTimer;
    // `reconnectNow` (resume) memakai Timer(Duration.zero); SIMPAN supaya bisa
    // dibatalkan saat chat ditutup (dulu tak terlacak → channel yatim).
    Timer? _resumeTimer;

    // Reconnect ter-debounce + backoff. Idempoten via flag `_reconnecting`.
    bool _reconnecting = false;
    void _scheduleChannelReconnect() {
      if (_isDead() || _reconnecting) return;
      _reconnecting = true;
      final base =
          _reconnectDelays[_reconnectAttempt.clamp(
            0,
            _reconnectDelays.length - 1,
          )];
      if (_reconnectAttempt < _reconnectDelays.length - 1) _reconnectAttempt++;
      final ms = (base * 1000 * (0.75 + _rng.nextDouble() * 0.5)).round();
      dlog('[ChatStream] reconnect dalam ${ms}ms (attempt=$_reconnectAttempt)');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(milliseconds: ms), () async {
        _reconnecting = false;
        if (_isDead()) return;
        if (!AppForeground.now) return; // jangan bangun proses saat background
        // Ambil pesan yang mungkin terlewat selama channel putus.
        unawaited(reload());
        // Buang channel lama lalu buat BARU (Supabase melarang subscribe
        // ulang pada instance yang sama).
        await dropChannel();
        // `channel != null` = sudah dibuka jalur lain (onListen/resume)
        // selama await → jangan buka kedua (yang satu jadi yatim).
        if (_isDead() || channel != null) return;
        try {
          openChannel();
        } catch (e) {
          dlog('[ChatStream] reconnect gagal: $e');
          _scheduleChannelReconnect();
        }
      });
    }

    requestReconnect = _scheduleChannelReconnect;

    // RESUME (2026-10-20): saat app ke background, socket realtime dibekukan/
    // diputus sistem & reconnect sengaja ditahan (hemat baterai). Tanpa hook
    // ini kanal tetap MATI setelah user kembali → event yang terjadi saat
    // background (mis. broadcast `view_once_seen`) hilang, kartu baru berubah
    // lewat poll 20 dtk ("masih ga realtime"). Di resume: reload untuk ambil
    // yang terlewat + hidupkan kanal SEKETIKA bila belum subscribed.
    void reconnectNow() {
      if (_isDead()) return;
      _reconnectTimer?.cancel();
      _resumeTimer?.cancel();
      _reconnecting = true;
      _resumeTimer = Timer(Duration.zero, () async {
        _reconnecting = false;
        if (_isDead() || _subscribedNow) return;
        await dropChannel();
        if (_isDead() || channel != null) return;
        try {
          openChannel();
        } catch (e) {
          dlog('[ChatStream] resume reconnect gagal: $e');
          _scheduleChannelReconnect();
        }
      });
    }

    var _fgWas = AppForeground.now;
    void _onFgChanged() {
      final now = AppForeground.now;
      if (now == _fgWas) return;
      _fgWas = now;
      if (!now || _isDead()) return;
      dlog(
        '[ChatStream] resume filter=$filterVal '
        'subscribed=$_subscribedNow',
      );
      unawaited(reload());
      // SELALU kanal baru: socket bisa "zombie" (status masih subscribed tapi
      // mati diam-diam karena freeze MIUI) — tanpa join ulang, event
      // berikutnya juga tidak akan sampai.
      reconnectNow();
    }

    AppForeground.isForeground.addListener(_onFgChanged);

    reload();

    // Fallback polling — JARING PENGAMAN saja, bukan jalur utama.
    //
    // Riwayat: 30s → 8s (2026-10: "terasa lama") → 20s (2026-10-18, audit).
    // 8s terlalu agresif: app tetap BANGUN 7,5×/menit hanya untuk memeriksa
    // kondisi, dan begitu realtime sedikit telat (>6s) langsung menembak
    // query. Terukur sebagai sumber beban timer global (audit: 58 timer
    // periodic vs ±3 di WhatsApp yang push-only). 20s = 3×/menit: masih
    // terasa responsif sebagai cadangan, beban turun ~60%.
    Timer? pollTimer;
    void startPoll() => pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        // BATERAI (P2): JANGAN poll saat app di-background (layar mati/tidak
        // dilihat). Dulu timer hidup terus → wake + query DB saat diam.
        // Pesan saat background tetap andal via FCM; sinkron saat resume.
        if (!AppForeground.now) return;
        // P1c (2026-10-18): JANGAN poll saat layar chat ini TIDAK terlihat.
        // Timer hidup selama sesi chat terbuka; kalau user sudah kembali ke
        // daftar chat / tab lain (layar di bawah tumpukan), polling hanya
        // membuang I/O. Gate sama seperti daftar chat (chat_service_private_
        // chatlist). Saat layar chat dibuka lagi, stream memicu reload sendiri.
        // Layar chat ini tidak terlihat (user sudah kembali ke daftar chat /
        // tab lain, tetapi sesi masih hidup di bawah tumpukan) → jangan poll.
        if (activeChatId.value != filterVal) return;
        // Realtime sehat (<25s ada event) → tak perlu fetch. Dulu 6s: terlalu
        // ketat sehingga sepi wajar pun dianggap "realtime mati" lalu memicu
        // query berulang saat chat memang sepi.
        if (DateTime.now().difference(lastRealtime).inSeconds < 25) return;
        reload();
      },
    );
    startPoll();

    // Load pesan lebih lama (pagination): ambil 100 pesan SEBELUM pesan tertua.
    Future<void> loadOlder() async {
      if (_loadingOlder || !_hasMore || _current.isEmpty || _isDead()) return;
      // Batas keras riwayat di memori tercapai → berhenti memuat (bounded).
      // `_hasMore` dibiarkan: riwayat di server memang masih ada.
      if (_current.length >= maxHistory) return;
      _loadingOlder = true;
      try {
        // Pakai kursor sesi (`_oldestFetchedTs`), BUKAN `_current.first` —
        // trim bisa memangkas depan `_current` sehingga first-nya lebih baru
        // dari yang sebenarnya sudah dimuat (lihat komentar `_trim`).
        final oldest = _oldestFetchedTs ?? _current.first.timestamp;
        var older = await fetchServer(before: oldest, limit: 100);
        if (_isDead()) return;
        // Pagination juga harus menghormati cutoff delete — pesan sebelum
        // cutoff tidak boleh muncul meski di-scroll ke atas.
        if (_hiddenCutoff != null) {
          older = older
              .where((m) => m.timestamp.isAfter(_hiddenCutoff!))
              .toList();
        }
        if (older.isEmpty) {
          _hasMore = false;
        } else {
          final seen = _current.map((m) => m.id).toSet();
          var newMsgs = older.reversed.where((m) => seen.add(m.id)).toList();
          if (newMsgs.isEmpty) {
            _hasMore = false;
          } else {
            // JANGAN `_trim()` di sini — itu membuang pesan yang BARU dimuat.
            // Ambil secukupnya sampai `maxHistory` (batch ASC → sisakan yang
            // terbaru), lalu naikkan jendela aktif supaya trim berikutnya
            // (pesan masuk / reload) tidak memangkas riwayat ini.
            final room = maxHistory - _current.length;
            if (newMsgs.length > room) {
              newMsgs = newMsgs.sublist(newMsgs.length - room);
            }
            _current = [...newMsgs, ..._current];
            if (_current.length > windowCap) windowCap = _current.length;
            // Stiker lama: isi path (halaman lama tak lewat loadPhotosAsync).
            final oldSk = [
              for (final m in newMsgs)
                if (m.type == 'sticker' && m.imageData.isEmpty) m,
            ];
            if (oldSk.isNotEmpty) {
              unawaited(
                fillStickerPaths(
                  sb: _sb,
                  table: table,
                  stickers: oldSk,
                  currentGetter: () => _current,
                  isClosed: () => _isDead(),
                  emit: _emit,
                  scheduleCacheSave: scheduleCacheSave,
                ),
              );
            }
            // Majukan kursor ke pesan terlama batch ini (lebih tua dari
            // kursor lama) agar paginasi berikutnya lanjut ke belakang.
            final first = newMsgs.first.timestamp;
            _oldestFetchedTs =
                _oldestFetchedTs == null || first.isBefore(_oldestFetchedTs!)
                ? first
                : _oldestFetchedTs;
            _emit();
            scheduleCacheSave();
          }
        }
      } catch (e) {
        dlog('[chat pagination] loadOlder error: $e');
      } finally {
        _loadingOlder = false;
        while (_loadMoreReqs.isNotEmpty) {
          _loadMoreReqs.removeAt(0).complete();
        }
      }
    }

    // Ambil foto satu pesan (icon refresh di bubble) — thumb dari PhotoCache
    // atau server, lalu update _current. Bubble pakai thumb supaya cepat;
    // full-res dimuat saat buka fullscreen.
    Future<void> fetchImage(String messageId) async {
      try {
        final idx = _current.indexWhere((x) => x.id == messageId);
        if (idx < 0) return;
        final m = _current[idx];
        final cached = await PhotoCache.instance.loadThumb(cacheKey, m.id);
        var data = cached;
        if (data == null) {
          if (_isDead()) return;
          final row = await _sb
              .from(table)
              .select('image_data,image_path')
              .eq('id', m.id)
              .maybeSingle();
          var full = (row?['image_data'] as String? ?? '').isNotEmpty
              ? (row?['image_data'] as String? ?? '')
              : (row?['image_path'] as String? ?? '');
          // PATH storage → download dari bucket sebelum disimpan ke cache.
          if (full.isNotEmpty && StoragePhotoService.instance.isPath(full)) {
            full = await StoragePhotoService.instance.download(full) ?? '';
          }
          if (full.isNotEmpty) {
            if (_isDead()) return;
            data = await PhotoCache.instance.save(cacheKey, m.id, full) ?? full;
          }
        }
        if (_isDead()) return;
        if (data != null && data.isNotEmpty) {
          // Indeks bisa bergeser selama await (loadOlder/insert) → cari ulang.
          final i = _current.indexWhere((x) => x.id == messageId);
          if (i < 0) return;
          _current[i] = _current[i].copyWith(imageData: data);
          _emit();
          scheduleCacheSave();
        }
      } catch (e) {
        dlog('[chat pagination] fetchImage $messageId error: $e');
      }
    }

    // Replay: broadcast tidak menyimpan emit terakhir — emit memori yang
    // terjadi sebelum StreamBuilder subscribe akan hilang. Kirim ulang
    // _current saat listener pertama datang supaya frame pertama instan.
    controller.onListen = () {
      if (sessionClosed && !controller.isClosed) {
        // Sesi DIPAKAI ULANG setelah onCancel: hidupkan lagi yang dimatikan
        // onCancel (channel, poll, hook resume) + ambil yang terlewat.
        sessionClosed = false;
        _reconnecting = false;
        _reconnectAttempt = 0;
        _fgWas = AppForeground.now;
        AppForeground.isForeground.addListener(_onFgChanged);
        startPoll();
        if (channel == null) {
          try {
            openChannel();
          } catch (e) {
            dlog('[ChatStream] reopen gagal: $e');
            _scheduleChannelReconnect();
          }
        }
        unawaited(reload());
      }
      if (_current.isNotEmpty && !_isDead()) {
        _emit();
      }
    };

    controller.onCancel = () {
      // Hentikan timer reconnect yang PENDING saat tak ada listener.
      // Tanpa ini: chat ditutup saat jaringan blip → timer reconnect menyala
      // → reload + openChannel membuat channel realtime baru yang tidak pernah
      // di-remove (langganan yatim: traffic & memori naik, "makin lama makin
      // lag").
      // CATATAN: sesi ini SENGAJA bisa di-subscribe ULANG (lihat komentar
      // `controller.close()` di bawah) — `sessionClosed` di-reset di onListen.
      // `sessionClosed` DULU (sebelum teardown) supaya status `closed` dari
      // removeChannel & semua kerja async yang masih berjalan diabaikan.
      sessionClosed = true;
      _reconnecting = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _resumeTimer?.cancel();
      _resumeTimer = null;
      pollTimer?.cancel();
      pollTimer = null;
      saveDebounce?.cancel();
      reloadDebounce?.cancel();
      AppForeground.isForeground.removeListener(_onFgChanged);
      // Snapshot list saat ini (referensi ringan) — kerja disk & teardown
      // channel DITUNDA ke microtask berikutnya agar TIDAK jatuh di frame
      // transisi pop (tutup chat). Dulu keduanya sinkron di sini → "tutup
      // private chat ngelag".
      // Tulis ini = flush SAAT ditutup; sesudahnya tak ada jalur lain yang
      // menulis cache (semua cek `_isDead`) — penting saat logout.
      final snapshot = cacheWindow();
      final sig = messageCacheSignature(snapshot);
      final needSave = snapshot.isNotEmpty && sig != lastSavedSig;
      if (needSave) lastSavedSig = sig;
      // Lepas referensi SEKARANG (sinkron); removeChannel-nya di microtask.
      final ch = channel;
      channel = null;
      _subscribedNow = false;
      scheduleMicrotask(() {
        if (needSave) {
          MessageCache.instance
              .saveMessages(cacheKey, snapshot)
              .catchError((_) {});
        }
        if (ch != null) {
          try {
            unawaited(_sb.removeChannel(ch).catchError((_) => 'error'));
          } catch (_) {} // cleanup best-effort
        }
        // P0b DIBATALKAN: JANGAN `controller.close()` di sini — stream ini
        // `broadcast` & bisa di-subscribe ULANG (`handle.stream.first` → cancel
        // → subscribe lagi). Menutup di onCancel merusak pemakaian berulang
        // ("Bad state: No element" saat loadOlder). Pelepasan `_current` cukup
        // lewat GC setelah tanpa listener.
      });
    };

    void markDeleted(String messageId, bool deleted) {
      if (_isDead()) return;
      final i = _current.indexWhere((m) => m.id == messageId);
      if (i < 0 || _current[i].isDeleted == deleted) return;
      if (deleted) {
        // Salinan BARU: `_current` bisa berbagi referensi dgn mem-cache /
        // tak dapat diubah — jangan mutasi di tempat.
        _current = List<MessageModel>.of(_current)
          ..[i] = _current[i].copyWith(isDeleted: true);
      } else {
        // Batal hapus: isi asli dipulihkan oleh refetch server (copyWith
        // terhapus sudah mengosongkan isi demi privasi).
        unawaited(reload());
        return;
      }
      _emit();
      // Tulis cache SEGERA (bukan debounce 2s) — user bisa langsung keluar.
      saveDebounce?.cancel();
      final win = cacheWindow();
      lastSavedSig = messageCacheSignature(win);
      unawaited(
        MessageCache.instance.saveMessages(cacheKey, win).catchError((_) {}),
      );
    }

    return ChatMessageStream(
      stream: controller.stream,
      loadOlder: loadOlder,
      fetchImage: fetchImage,
      reload: reload,
      revision: revision,
      markDeleted: markDeleted,
    );
  }
}
