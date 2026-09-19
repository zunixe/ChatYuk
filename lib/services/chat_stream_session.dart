import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../utils.dart';
import 'message_cache.dart';
import 'photo_cache.dart';
import 'storage_photo_service.dart';

// Concurrency limiter: max N operasi paralel, sisanya antri.
class _Semaphore {
  final int max;
  int _count = 0;
  final _waiters = <Completer<void>>[];
  _Semaphore(this.max);
  Future<void> acquire() async {
    if (_count < max) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    _count--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      _count++;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

// Handle stream chat — expose stream + aksi loadOlder untuk pagination.
class ChatMessageStream {
  final Stream<List<MessageModel>> stream;
  final Future<void> Function() loadOlder;
  final Future<void> Function(String messageId) fetchImage;

  /// Fetch ulang pesan terbaru dari server — jaring pengaman kalau event
  /// Realtime miss (channel drop) supaya bubble pending tidak nyangkut.
  final Future<void> Function() reload;
  const ChatMessageStream({
    required this.stream,
    required this.loadOlder,
    required this.fetchImage,
    required this.reload,
  });
}

/// Sesi stream pesan satu chat (room / private). Isi lengkap closure
/// `_cachedMessagesStream` lama dipindahkan ke sini; `ChatService` hanya
/// menjadi wrapper tipis yang membuat instance ini.
class ChatStreamSession {
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
  })  : _sb = sb,
        isPrivate = cacheKey.startsWith('private_'),
        table = cacheKey.startsWith('private_') ? 'private_messages' : 'messages',
        filterKey = cacheKey.startsWith('private_') ? 'chat_id' : 'room_id',
        filterVal = cacheKey.split('_').skip(1).join('_'),
        _needsPhotoFill = needsPhotoFill,
        _downloadVoiceToCache = downloadVoiceToCache,
        _prefetchVoiceBytes = prefetchVoiceBytes;

  // Cache cutoff delete per chat (TTL 60 dtk) — hindari query private_chats
  // berulang tiap reload. Di-invalidasi saat ada event realtime pada chat.
  static final Map<String, ({DateTime? ts, DateTime fetchedAt})>
      _hiddenCutoffCache = {};

  /// - loadCache dan fetchServer jalan PARALEL untuk tampilan secepat mungkin.
  /// - INSERT event langsung di-append ke list tanpa refetch (0 network round-trip).
  /// - UPDATE/DELETE tetap refetch karena perlu reorder.
  /// - Poll fallback hanya jalan kalau realtime diam > 25s (event terlewat),
  ///   supaya tidak duplikasi pekerjaan realtime tiap 30 detik.
  ChatMessageStream start() {
    final controller = StreamController<List<MessageModel>>.broadcast();
    var _current = <MessageModel>[];
    var _loadingOlder = false;
    var _hasMore = true;
    final _loadMoreReqs = <Completer<void>>[];

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
      if (controller.isClosed || _current.isEmpty) return;
      saveDebounce?.cancel();
      saveDebounce = Timer(const Duration(seconds: 2), () async {
        if (controller.isClosed) return;
        final sig = _current.isEmpty
            ? ''
            : '${_current.length}:${_current.last.id}';
        if (sig == lastSavedSig) return;
        lastSavedSig = sig;
        try {
          await MessageCache.instance.saveMessages(cacheKey, _current);
        } catch (e) {
          dlog('[ChatService] clearViewOnceImage ignored: $e');
        }
      });
    }

    // Kolom tanpa image_data — foto diambil terpisah (PhotoCache / download
    // lazy) supaya buka chat tetap cepat walau ada ratusan foto.
    const privateCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at,edited,is_deleted,image_path,voice_path,duration_ms,is_forwarded,mentions';
    const roomCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at,edited,is_deleted,image_path,voice_path,duration_ms,replied_to_id,replied_to_text,replied_to_sender_name,is_forwarded,mentions';
    const replyCols = 'replied_to_id,replied_to_text,replied_to_sender_name';
    final cols = isPrivate ? '$privateCols,$replyCols' : roomCols;

    // Sync foto otomatis: server → file lokal terenkripsi. Download lazy
    // (paralel) hanya untuk pesan yang fotonya belum ada di lokal.
    final photoQueue = <MessageModel>[];
    var downloading = 0;
    const maxConcurrentPhotos = 5;

    // Batasi load foto lokal paralel — 100 foto decrypt sekaligus bikin
    // buka chat lambat. Max 4 parallel, sisanya antri.
    final _photoLoadGate = _Semaphore(4);

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
            final chunk = batch.skip(i).take(4).toList();
            final results = await Future.wait(
              chunk.map((m) async {
                var data = byId[m.id] ?? '';
                if (data.isNotEmpty &&
                    StoragePhotoService.instance.isPath(data)) {
                  data =
                      await StoragePhotoService.instance.download(data) ?? '';
                }
                return data;
              }),
            );
            for (var j = 0; j < chunk.length; j++) {
              final m = chunk[j];
              final data = results[j];
              dlog('[PHOTO-DBG] drain ${m.id} srcLen=${(byId[m.id] ?? '').length} dlLen=${data.length}');
              if (data.isEmpty) continue;
              // save() menyimpan full-res + membuat thumbnail (dikembalikan).
              // Bubble pakai thumbnail supaya decode cepat; full-res di PhotoCache.
              final thumb = await PhotoCache.instance.save(
                cacheKey,
                m.id,
                data,
              );
              if (controller.isClosed) return;
              final idx = _current.indexWhere((x) => x.id == m.id);
              if (idx >= 0 && _needsPhotoFill(_current[idx])) {
                _current[idx] = _current[idx].copyWith(
                  imageData: thumb ?? data,
                );
                controller.add(List.unmodifiable(_current));
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
    void loadPhotosAsync(List<MessageModel> models) {
      if (models.isEmpty) return;
      // Voice: prefetch audio TERBARU di background (lazy) supaya tap play
      // langsung dari disk. Dibatasi 10 terbaru agar hemat kuota; voice lama
      // tetap on-demand saat di-tap (dengan spinner di bubble).
      final voices = models
          .where((m) =>
              m.type == 'voice' &&
              m.imageData.isNotEmpty &&
              StoragePhotoService.instance.isVoicePath(m.imageData))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (voices.isNotEmpty) {
        unawaited(() async {
          for (final m in voices.take(10)) {
            if (controller.isClosed) return;
            await _prefetchVoiceBytes(m.imageData);
          }
        }());
      }
      final photos = models.where((m) {
        return m.type == 'image' ||
            m.type == 'view_once' ||
            m.type == 'view_once_expired';
      }).toList();
      if (photos.isEmpty) return;
      _photoLoadGate.run(() async {
        for (var i = 0; i < photos.length; i += 20) {
          if (controller.isClosed) return;
          final chunk = photos.skip(i).take(20).map((m) => m.id).toList();
          final map = await PhotoCache.instance.loadMany(cacheKey, chunk);
          if (controller.isClosed) return;
          for (final m in photos.skip(i).take(20)) {
            final data = map[m.id];
            if (data == null || data.isEmpty) {
              queuePhotoDownload(m);
              continue;
            }
            final idx = _current.indexWhere((x) => x.id == m.id);
            if (idx >= 0 && _needsPhotoFill(_current[idx])) {
              _current[idx] = _current[idx].copyWith(imageData: data);
              controller.add(List.unmodifiable(_current));
              scheduleCacheSave();
            }
          }
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
          dlog('[PHOTO-DBG] fetchServer ${m.id} type=${m.type} imgLen=${m.imageData.length} head=${m.imageData.isEmpty ? '' : m.imageData.substring(0, m.imageData.length > 30 ? 30 : m.imageData.length)}');
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
          if (mem != null && mem.isNotEmpty && !controller.isClosed) {
            _current = mem;
            controller.add(List.unmodifiable(_current));
            loadPhotosAsync(mem);
          }
        }

        // Emit cache lokal (SQLite) tanpa tunggu cutoff network — frame
        // pertama tetap cepat bila memori miss. Cutoff & server menyusul.
        final cutoffF = fetchHiddenCutoff();
        final cacheF = _current.isEmpty
            ? MessageCache.instance.loadMessages(cacheKey)
            : Future<List<MessageModel>>.value(const <MessageModel>[]);
        final cached = await cacheF;
        if (cached.isNotEmpty && !controller.isClosed) {
          _current = cached;
          controller.add(List.unmodifiable(_current));
          loadPhotosAsync(cached);
        }
        _hiddenCutoff = await cutoffF;
        if (controller.isClosed) return;
        if (_hiddenCutoff != null && _current.isNotEmpty) {
          final filtered = _current
              .where((m) => m.timestamp.isAfter(_hiddenCutoff!))
              .toList();
          if (filtered.length != _current.length) {
            _current = filtered;
            controller.add(List.unmodifiable(_current));
          }
        }
        final swServer = Stopwatch()..start();
        final server = await fetchServer(limit: 100);
        dlog(
          '[CACHE-TIME] $cacheKey server=${swServer.elapsedMilliseconds}ms n=${server.length}',
        );
        if (controller.isClosed) return;
        if (_hiddenCutoff != null) {
          server.removeWhere((m) => !m.timestamp.isAfter(_hiddenCutoff!));
        }
        // MERGE: server DESC → ASC. _current yang belum ada di server
        // disisipkan kronologis (bukan selalu di akhir) — realtime bisa
        // datang tidak urut & cache bisa berisi pesan lama di luar window
        // fetch 100 terbaru.
        final merged = List<MessageModel>.from(server.reversed);
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
        controller.add(List.unmodifiable(_current));
        scheduleCacheSave();
        // Foto di-load background — teks tidak menunggu decrypt foto.
        loadPhotosAsync(merged);
      } catch (e) {
        dlog('[_cachedMessagesStream] fetch error: $e');
        // Fallback: tampilkan cache hanya kalau server gagal.
        // Filter hiddenCutoff TETAP diterapkan — cache lokal bisa berisi
        // history sebelum delete yang tidak boleh muncul lagi.
        MessageCache.instance.loadMessages(cacheKey).then((cached) {
          if (cached.isNotEmpty && !controller.isClosed && _current.isEmpty) {
            var list = cached;
            if (_hiddenCutoff != null) {
              list = list
                  .where((m) => m.timestamp.isAfter(_hiddenCutoff!))
                  .toList();
            }
            if (list.isEmpty) return;
            _current = list;
            controller.add(List.unmodifiable(_current));
            loadPhotosAsync(list);
          }
        });
      } finally {
        _reloading = false;
        // Ada permintaan reload yang datang saat proses berjalan → jalankan
        // sekali lagi supaya tidak ada event yang hilang.
        if (_reloadQueued && !controller.isClosed) {
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
    final channelName = 'msg-$cacheKey';
    final channel = _sb.channel(channelName);

    // INSERT: append langsung dari payload — tidak perlu round-trip ke server
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: filterKey,
        value: filterVal,
      ),
      callback: (payload) async {
        _hiddenCutoffCache.remove(filterVal);
        if (controller.isClosed) return;
        try {
          final row = payload.newRecord;
          if (row[filterKey]?.toString() != filterVal) return;
          var msg = MessageModel.fromMap('${row['id']}', snakeToCamel(row));
          if (_current.any((m) => m.id == msg.id)) return; // dedupe
          if (_hiddenCutoff != null && !msg.timestamp.isAfter(_hiddenCutoff!))
            return;
          // Foto dari realtime: buat thumbnail DULU sebelum emit — bubble langsung
          // pakai thumb (decode cepat, ala WhatsApp). Kalau thumb gagal dibuat,
          // fallback ke imageData penuh supaya gambar tetap muncul (tidak spinner
          // selamanya). Full-res tersimpan di PhotoCache untuk fullscreen.
          // VOICE: jangan proses sebagai image — path m4a langsung dipakai VoiceBubble.
          if (msg.imageData.isNotEmpty && msg.type != 'voice') {
            try {
              var data = msg.imageData;
              // PATH storage → download dari bucket sebelum dibuat thumbnail.
              if (StoragePhotoService.instance.isPath(data)) {
                data = await StoragePhotoService.instance.download(data) ?? '';
              }
              if (data.isNotEmpty) {
                final thumb = await PhotoCache.instance.save(
                  cacheKey,
                  msg.id,
                  data,
                );
                if (!controller.isClosed && thumb != null && thumb.isNotEmpty) {
                  msg = msg.copyWith(imageData: thumb);
                }
              }
            } catch (e) {
              dlog('[photo save] ${msg.id} error: $e');
            }
          } else if (msg.type == 'image' ||
              msg.type == 'view_once' ||
              msg.type == 'view_once_expired') {
            queuePhotoDownload(msg);
          } else if (msg.type == 'voice') {
            // Voice: unduh audio ke cache lokal via PhotoCache (tanpa thumbnail)
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
          lastRealtime = DateTime.now();
          dlog(
            '[DEBUG-READ] realtime INSERT table=$table msg=${msg.id} filter=$filterVal',
          );
          if (msg.type == 'image' || msg.type == 'view_once' || msg.type == 'voice') {
            dlog('[PHOTO-DBG] rt-insert ${msg.id} type=${msg.type} imgLen=${msg.imageData.length} head=${msg.imageData.isEmpty ? '' : msg.imageData.substring(0, msg.imageData.length > 30 ? 30 : msg.imageData.length)}');
          }
          controller.add(List.unmodifiable(_current));
          scheduleCacheSave();
        } catch (_) {
          scheduleReload();
        }
      },
    );
    // UPDATE: parse payload untuk update partial (jangan refetch full)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: table,
      callback: (payload) {
        _hiddenCutoffCache.remove(filterVal);
        lastRealtime = DateTime.now();
        try {
          final newRecord = payload.newRecord;
          if (newRecord['id'] == null) {
            scheduleReload();
            return;
          }
          final idx = _current.indexWhere((x) => x.id == newRecord['id']);
          if (idx < 0) {
            scheduleReload();
            return;
          }
          final updated = _current[idx].copyWith(
            text: newRecord.containsKey('text')
                ? (newRecord['text'] as String? ?? _current[idx].text)
                : _current[idx].text,
            edited: newRecord.containsKey('edited')
                ? (newRecord['edited'] as bool? ?? false)
                : _current[idx].edited,
            imageData: newRecord.containsKey('image_data')
                ? (newRecord['image_data'] as String? ??
                      _current[idx].imageData)
                : _current[idx].imageData,
            type: newRecord.containsKey('type')
                ? (newRecord['type'] as String? ?? _current[idx].type)
                : _current[idx].type,
            isDeleted: newRecord.containsKey('is_deleted')
                ? (newRecord['is_deleted'] as bool? ?? false)
                : _current[idx].isDeleted,
          );
          _current[idx] = updated;
          controller.add(List.unmodifiable(_current));
          scheduleCacheSave();
        } catch (_) {
          scheduleReload();
        }
      },
    );
    channel.onPostgresChanges(
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
        lastRealtime = DateTime.now();
        scheduleReload();
      },
    );
    channel.onBroadcast(event: 'new_message', callback: (payload, [ref]) async {
      _hiddenCutoffCache.remove(filterVal);
      lastRealtime = DateTime.now();
      if (controller.isClosed) return;
      try {
        final data = payload;
        if (data['chat_id']?.toString() != filterVal && data['room_id']?.toString() != filterVal) return;
        var msg = MessageModel.fromMap(data['id']?.toString() ?? 'bc-${DateTime.now().microsecondsSinceEpoch}', snakeToCamel(data));
        if (_current.any((m) => m.id == msg.id)) return;
        if (msg.imageData.isNotEmpty) {
          try {
            var d = msg.imageData;
            if (StoragePhotoService.instance.isPath(d) || StoragePhotoService.instance.isVoicePath(d)) {
              d = await StoragePhotoService.instance.download(d) ?? '';
            }
            if (d.isNotEmpty) {
              final thumb = await PhotoCache.instance.save(cacheKey, msg.id, d);
              if (!controller.isClosed && thumb != null && thumb.isNotEmpty) msg = msg.copyWith(imageData: thumb);
            }
          } catch (_) {}
        }
        // Sisipkan kronologis
        var idx = _current.indexWhere((m) => m.timestamp.isAfter(msg.timestamp));
        if (idx < 0) { _current.add(msg); } else { _current.insert(idx, msg); }
        controller.add(List.unmodifiable(_current));
        scheduleCacheSave();
      } catch (_) {}
    });
    channel.subscribe();
    reload();

    // Fallback polling: hanya jalan kalau realtime diam > 25s.
    // Saat realtime sehat (tangkap INSERT/UPDATE/DELETE), tidak ada
    // fetch redundant tiap 30 detik.
    final pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (DateTime.now().difference(lastRealtime).inSeconds < 25) return;
      reload();
    });

    // Load pesan lebih lama (pagination): ambil 100 pesan SEBELUM pesan tertua.
    Future<void> loadOlder() async {
      if (_loadingOlder || !_hasMore || _current.isEmpty || controller.isClosed)
        return;
      _loadingOlder = true;
      try {
        final oldest = _current.first.timestamp;
        var older = await fetchServer(before: oldest, limit: 100);
        if (controller.isClosed) return;
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
          final newMsgs = older.reversed.where((m) => seen.add(m.id)).toList();
          if (newMsgs.isEmpty) {
            _hasMore = false;
          } else {
            _current = [...newMsgs, ..._current];
            controller.add(List.unmodifiable(_current));
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
            data = await PhotoCache.instance.save(cacheKey, m.id, full) ?? full;
          }
        }
        if (controller.isClosed) return;
        if (data != null && data.isNotEmpty) {
          _current[idx] = _current[idx].copyWith(imageData: data);
          controller.add(List.unmodifiable(_current));
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
      if (_current.isNotEmpty && !controller.isClosed) {
        controller.add(List.unmodifiable(_current));
      }
    };

    controller.onCancel = () {
      pollTimer.cancel();
      saveDebounce?.cancel();
      reloadDebounce?.cancel();
      // Flush cache pending kalau ada data yang belum tersimpan.
      if (_current.isNotEmpty) {
        final sig = _current.isEmpty
            ? ''
            : '${_current.length}:${_current.last.id}';
        if (sig != lastSavedSig) {
          MessageCache.instance
              .saveMessages(cacheKey, _current)
              .catchError((_) {});
        }
      }
      _sb.removeChannel(channel);
    };

    return ChatMessageStream(
      stream: controller.stream,
      loadOlder: loadOlder,
      fetchImage: fetchImage,
      reload: reload,
    );
  }
}
