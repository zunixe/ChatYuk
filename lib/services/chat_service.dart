import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../config/supabase_config.dart';
import 'realtime_hub.dart';
import '../config/gifts.dart';
import '../services/message_cache.dart';
import '../services/photo_cache.dart';
import '../services/storage_photo_service.dart';
import '../utils.dart';

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

class ChatService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // Cache avatar (path → base64) — hindari download ulang tiap fetch online.
  final Map<String, String> _avatarCache = {};
  static const _avatarCacheMax = 100;

  Future<String> _avatarB64(String path) async {
    final cached = _avatarCache[path];
    if (cached != null) return cached;
    final b64 = await StoragePhotoService.instance.download(path) ?? '';
    if (b64.isNotEmpty) {
      if (_avatarCache.length >= _avatarCacheMax) {
        _avatarCache.remove(_avatarCache.keys.first);
      }
      _avatarCache[path] = b64;
    }
    return b64;
  }

  // ── Room Chat ──

  ChatMessageStream getRoomMessages(String roomId) {
    return _cachedMessagesStream(cacheKey: 'room_$roomId');
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
  }) async {
    // Validasi tipe pesan
    if (!['text', 'image', 'view_once'].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image data jika ada — boleh base64 (lama) ATAU path storage (baru)
    if (imageData.isNotEmpty &&
        !isValidImageBase64(imageData) &&
        !StoragePhotoService.instance.isPath(imageData)) {
      throw Exception('Invalid image data');
    }
    if (type == 'text' && (text.isEmpty || text.length > 2000)) return;
    await _sb.from('messages').insert({
      'room_id': roomId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': imageData,
    });
  }

  // ── Private Chat ──

  /// Id chat 1:1 deterministik — urutan uid di-sort. Bisa dipanggil tanpa
  /// DB (fallback saat upsert gagal), hasilnya selalu sama dgn sisi lain.
  String privateChatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _chatId(String uid1, String uid2) => privateChatId(uid1, uid2);

  ChatMessageStream getPrivateChatMessages(String chatId) {
    return _cachedMessagesStream(cacheKey: 'private_$chatId');
  }

  /// Edit teks pesan sendiri di private chat. RLS menjamin hanya sender_id
  /// (auth.uid) yang boleh mengubah pesannya. `edited` ditandai true bila
  /// kolom migrasi sudah ada; kalau belum, fallback hanya ubah `text`.
  Future<bool> editPrivateMessage(String messageId, String newText) async {
    try {
      await _sb
          .from('private_messages')
          .update({'text': newText, 'edited': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      debugPrint('[ChatService] editPrivateMessage (with edited) error: $e');
      try {
        await _sb
            .from('private_messages')
            .update({'text': newText})
            .eq('id', messageId);
        return true;
      } catch (e2) {
        debugPrint('[ChatService] editPrivateMessage (text only) error: $e2');
        return false;
      }
    }
  }

  /// Hapus pesan sendiri (soft delete) — tandai is_deleted = true.
  /// RLS menjamin hanya sender_id (auth.uid) yang boleh mengubah pesannya.
  Future<bool> deletePrivateMessage(String messageId) async {
    try {
      await _sb
          .from('private_messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
      return true;
    } catch (e) {
      debugPrint('[ChatService] deletePrivateMessage error: $e');
      return false;
    }
  }

  /// - loadCache dan fetchServer jalan PARALEL untuk tampilan secepat mungkin.
  /// - INSERT event langsung di-append ke list tanpa refetch (0 network round-trip).
  /// - UPDATE/DELETE tetap refetch karena perlu reorder.
  /// - Poll fallback hanya jalan kalau realtime diam > 25s (event terlewat),
  ///   supaya tidak duplikasi pekerjaan realtime tiap 30 detik.
  ChatMessageStream _cachedMessagesStream({required String cacheKey}) {
    final isPrivate = cacheKey.startsWith('private_');
    final table = isPrivate ? 'private_messages' : 'messages';
    final filterKey = isPrivate ? 'chat_id' : 'room_id';
    final filterVal = cacheKey.split('_').skip(1).join('_');

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
          debugPrint('[ChatService] clearViewOnceImage ignored: $e');
        }
      });
    }

    // Kolom tanpa image_data — foto diambil terpisah (PhotoCache / download
    // lazy) supaya buka chat tetap cepat walau ada ratusan foto.
    const privateCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at,edited,is_deleted';
    const roomCols =
        'id,sender_id,sender_name,sender_gender,text,type,is_registered,created_at';
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
              .select('id,image_data')
              .inFilter('id', ids);
          final byId = {
            for (final r in rows)
              '${r['id']}': (r['image_data'] as String? ?? ''),
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
              if (idx >= 0 && _current[idx].imageData.isEmpty) {
                _current[idx] = _current[idx].copyWith(
                  imageData: thumb ?? data,
                );
                controller.add(List.unmodifiable(_current));
                scheduleCacheSave();
              }
            }
          }
        } catch (e) {
          debugPrint(
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
            if (idx >= 0 && _current[idx].imageData.isEmpty) {
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
      return rows
          .map((row) => MessageModel.fromMap('${row['id']}', snakeToCamel(row)))
          .toList();
    }

    // Ambil cutoff delete user ini (UTC → local). null = tidak pernah delete.
    Future<DateTime?> fetchHiddenCutoff() async {
      if (!isPrivate) return null;
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return null;
      try {
        final row = await _sb
            .from('private_chats')
            .select('hidden_at')
            .eq('chat_id', filterVal)
            .maybeSingle();
        if (row == null) return null;
        final map = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
        final v = map[uid];
        if (v == null) return null;
        return DateTime.tryParse('$v')?.toLocal();
      } catch (_) {
        return null;
      }
    }

    Future<void> reload() async {
      try {
        // Emit cache lokal DULU tanpa tunggu cutoff network — frame pertama
        // instant. Cutoff & server menyusul dan mengkoreksi di emit berikutnya.
        final cutoffF = fetchHiddenCutoff();
        final cacheF = _current.isEmpty
            ? MessageCache.instance.loadMessages(cacheKey)
            : Future<List<MessageModel>>.value(const <MessageModel>[]);
        final cached = await cacheF;        if (cached.isNotEmpty && !controller.isClosed) {
          _current = cached;
          controller.add(_current);
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
            controller.add(_current);
          }
        }
        final swServer = Stopwatch()..start();
        final server = await fetchServer(limit: 100);
        debugPrint(
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
        controller.add(_current);
        scheduleCacheSave();
        // Foto di-load background — teks tidak menunggu decrypt foto.
        loadPhotosAsync(merged);
      } catch (e) {
        debugPrint('[_cachedMessagesStream] fetch error: $e');
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
            controller.add(_current);
            loadPhotosAsync(list);
          }
        });
      }
    }

    final channelName = 'msg-${cacheKey.hashCode}';
    final channel = _sb.channel(channelName);

    // INSERT: append langsung dari payload — tidak perlu round-trip ke server
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: table,
      callback: (payload) async {
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
          if (msg.imageData.isNotEmpty) {
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
              debugPrint('[photo save] ${msg.id} error: $e');
            }
          } else if (msg.type == 'image' ||
              msg.type == 'view_once' ||
              msg.type == 'view_once_expired') {
            queuePhotoDownload(msg);
          }
          // Sisipkan di posisi kronologis yang benar (ascending by timestamp),
          // bukan selalu di akhir — pesan realtime bisa tiba tidak urut
          // (mis. pesan riwayat call datang SETELAH user kirim chat baru).
          var insertAt = _current.length;
          for (var i = _current.length - 1; i >= 0; i--) {
            if (_current[i].timestamp.isAfter(msg.timestamp)) {
              insertAt = i;
            } else {
              break;
            }
          }
          _current = [
            ..._current.sublist(0, insertAt),
            msg,
            ..._current.sublist(insertAt),
          ];
          lastRealtime = DateTime.now();
          debugPrint(
            '[DEBUG-READ] realtime INSERT table=$table msg=${msg.id} filter=$filterVal',
          );
          controller.add(_current);
          scheduleCacheSave();
        } catch (_) {
          reload();
        }
      },
    );
    // UPDATE: parse payload untuk update partial (jangan refetch full)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: table,
      callback: (payload) {
        lastRealtime = DateTime.now();
        try {
          final newRecord = payload.newRecord;
          if (newRecord['id'] == null) {
            reload();
            return;
          }
          final idx = _current.indexWhere((x) => x.id == newRecord['id']);
          if (idx < 0) {
            reload();
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
          reload();
        }
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: table,
      callback: (_) {
        lastRealtime = DateTime.now();
        reload();
      },
    );
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
        debugPrint('[chat pagination] loadOlder error: $e');
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
              .select('image_data')
              .eq('id', m.id)
              .maybeSingle();
          var full = row?['image_data'] as String? ?? '';
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
        debugPrint('[chat pagination] fetchImage $messageId error: $e');
      }
    }

    controller.onCancel = () {
      pollTimer.cancel();
      saveDebounce?.cancel();
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

  Future<String> startPrivateChat({
    required String myUid,
    required String otherUid,
    required String myName,
    required String otherName,
    String myGender = '',
    String otherGender = '',
    String myCountry = '',
    String otherCountry = '',
    int myAge = 0,
    int otherAge = 0,
  }) async {
    final chatId = _chatId(myUid, otherUid);
    await _sb
        .from('private_chats')
        .upsert(
          {
            'chat_id': chatId,
            'participants': [myUid, otherUid],
            'participant_names': {myUid: myName, otherUid: otherName},
            'participant_genders': {myUid: myGender, otherUid: otherGender},
            'participant_locations': {myUid: myCountry, otherUid: otherCountry},
            'participant_ages': {myUid: myAge, otherUid: otherAge},
            'last_message': '',
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'chat_id',
          ignoreDuplicates: true,
        );
    return chatId;
  }

  /// Cek apakah user masih aktif (akun tidak dihapus).
  /// Dipakai sebelum startPrivateChat — policy RLS menolak insert chat
  /// kalau salah satu participant sudah tidak ada di profiles.
  Future<bool> isUserActive(String uid) async {
    try {
      final row = await _sb
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
  }) async {
    // Validasi tipe pesan
    if (!['text', 'image', 'view_once', 'call'].contains(type)) {
      throw Exception('Invalid message type');
    }
    // Validasi image data jika ada — boleh base64 (lama) ATAU path storage (baru)
    if (type != 'call' &&
        imageData.isNotEmpty &&
        !isValidImageBase64(imageData) &&
        !StoragePhotoService.instance.isPath(imageData)) {
      throw Exception('Invalid image data');
    }
    // Batasi panjang teks pesan
    if (text.length > 2000) {
      throw Exception('Message too long (max 2000 chars)');
    }

    // Kirim pesan = chat muncul lagi di list (history lama tetap disembunyikan).
    // Optimasi: chat yang sudah tampil di list pasti tidak hidden — skip
    // unhideChat supaya kirim cukup 1 round-trip.
    final visibleInList =
        _privateChatsLast[senderId]?.any((c) => c.chatId == chatId) ?? false;
    if (!visibleInList) {
      await unhideChat(senderId, chatId);
    }

    await _sb.from('private_messages').insert({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_gender': senderGender,
      'text': text,
      'type': type,
      'image_data': imageData,
      if (repliedToId != null) 'replied_to_id': repliedToId,
      if (repliedToText != null) 'replied_to_text': repliedToText,
      if (repliedToSenderName != null)
        'replied_to_sender_name': repliedToSenderName,
    });
  }

  /// Kirim koin ke lawan bicara. Server yang memvalidasi & memotong koin.
  /// Return {ok, points}. Lempar PostgrestException bila gagal.
  Future<Map<String, dynamic>> sendCoins(
    String chatId,
    String receiverId,
    int amount,
  ) async {
    final res = await _sb.rpc(
      'send_coins',
      params: {
        'p_chat_id': chatId,
        'p_receiver_id': receiverId,
        'p_amount': amount,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Kirim hadiah (gift) ke lawan bicara. Server memotong koin pengirim,
  /// ambil platform cut, kredit net ke penerima. Return {ok, points, net, cut}.
  Future<Map<String, dynamic>> sendGift(
    String chatId,
    String receiverId,
    String giftId,
  ) async {
    final res = await _sb.rpc(
      'send_gift',
      params: {
        'p_chat_id': chatId,
        'p_receiver_id': receiverId,
        'p_gift_id': giftId,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Daftar hadiah dari server (fallback ke katalog lokal bila gagal).
  Future<List<Map<String, dynamic>>> listGifts() async {
    try {
      final res = await _sb.rpc('list_gifts');
      if (res is List) return res.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[ChatService] listGifts fallback local: $e');
    }
    return kGiftCatalog
        .map(
          (g) => {
            'id': g.id,
            'emoji': g.emoji,
            'name_id': g.nameId,
            'name_en': g.nameEn,
            'coins': g.coins,
          },
        )
        .toList();
  }

  /// Tandai view_once message sebagai expired setelah dilihat.
  /// image_data DIKEEP di DB (admin masih bisa melihat) — hanya type yang
  /// diubah. Kontrol "boleh lihat/tidak" dilakukan di sisi UI.
  Future<void> clearViewOnceImage(
    String messageId, {
    bool isRoom = false,
  }) async {
    try {
      await _sb
          .from(isRoom ? 'messages' : 'private_messages')
          .update({'type': 'view_once_expired'})
          .eq('id', messageId);
    } catch (e) {
      debugPrint('[ChatService] clearViewOnceImage ignored: $e');
    }
  }

  // Map: userId -> list of reload callbacks untuk getMyPrivateChats streams
  final Map<String, List<void Function()>> _chatReloaders = {};
  // Cache stream per myUid agar tidak buat channel baru tiap subscribe
  final Map<String, StreamController<List<PrivateChatInfo>>>
  _privateChatsStreams = {};
  // Snapshot terakhir per myUid — dikirim ke subscriber baru (mis. balik ke
  // sub-tab Pesan) supaya list langsung tampil tanpa spinner broadcast-miss.
  final Map<String, List<PrivateChatInfo>> _privateChatsLast = {};
  // Chat yang di-hide per myUid — dipakai pesan masuk untuk skip query.
  final Map<String, Set<String>> _privateChatsHidden = {};
  // Waktu reload terakhir per myUid — dipakai untuk skip refetch 500 row
  // saat sub-tab Pesan di-mount ulang dan snapshot realtime masih fresh.
  final Map<String, DateTime> _lastChatReloadAt = {};

  Future<void> markAsRead(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      // Update snapshot lokal langsung (tanpa refetch 500 row) — event
      // realtime dari RPC ini menyusul dan menyinkronkan via _applyChatEvent.
      _applyLocalRead(uid, chatId);
    } catch (e) {
      debugPrint('[DEBUG-READ] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  /// Tandai dibaca atas nama peserta dari monitor admin. Pakai RPC khusus
  /// (SECURITY DEFINER + guard admin) karena akun admin bukan participant,
  /// sehingga mark_chat_read biasa (RLS participants) tidak mengubah apa-apa.
  Future<void> markAsReadAdmin(String chatId, String uid) async {
    try {
      await _sb.rpc(
        'admin_mark_chat_read',
        params: {'p_chat_id': chatId, 'p_uid': uid},
      );
      _applyLocalRead(uid, chatId);
    } catch (e) {
      debugPrint('[DEBUG-READ-ADMIN] RPC FAIL chat=$chatId uid=$uid err=$e');
    }
  }

  /// Persist list chat (debounced) — supaya setelah app ditutup lalu dibuka
  /// lagi, list tampil instan dari cache sebelum fetch server menyusul.
  final Map<String, Timer> _chatListSaveTimers = {};

  void _scheduleChatListSave(String myUid) {
    _chatListSaveTimers[myUid]?.cancel();
    _chatListSaveTimers[myUid] = Timer(const Duration(seconds: 2), () {
      final rows = _privateChatsLast[myUid];
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance
          .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
    });
  }

  /// Update unread/lastRead di snapshot lokal list chat — UI instan tanpa
  /// refetch. Snapshot tetap akurat karena realtime mengirim row lengkap.
  void _applyLocalRead(String myUid, String chatId) {
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final chat = last[idx];
    if ((chat.unreadCounts[myUid] ?? 0) == 0) return;
    final updated = chat.copyWith(
      unreadCounts: {...chat.unreadCounts, myUid: 0},
      lastReadAt: {...chat.lastReadAt, myUid: DateTime.now()},
    );
    final list = List.of(last)..[idx] = updated;
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  /// Terapkan row private_chats dari payload realtime ke snapshot lokal —
  /// tanpa query tambahan. Row dikirim lengkap oleh Supabase Realtime.
  void _applyChatEvent(String myUid, Map<String, dynamic> row) {
    final chat = _rowToPrivateChat(row);
    final hiddenBy = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    if (hiddenBy.contains(myUid)) {
      _privateChatsHidden.putIfAbsent(myUid, () => {}).add(chat.chatId);
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    _privateChatsHidden[myUid]?.remove(chat.chatId);
    if (chat.messageCount <= 0) {
      _removeLocalChat(myUid, chat.chatId);
      return;
    }
    final last = _privateChatsLast[myUid] ?? [];
    final idx = last.indexWhere((c) => c.chatId == chat.chatId);
    final List<PrivateChatInfo> list;
    if (idx >= 0) {
      list = List.of(last)..[idx] = chat;
    } else {
      list = [chat, ...last];
    }
    // Jaga urutan DESC by lastMessageAt — item baru/berubah bisa pindah posisi.
    list.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  void _removeLocalChat(String myUid, String chatId) {
    final last = _privateChatsLast[myUid];
    if (last == null) return;
    final idx = last.indexWhere((c) => c.chatId == chatId);
    if (idx < 0) return;
    final list = List.of(last)..removeAt(idx);
    _privateChatsLast[myUid] = list;
    _lastChatReloadAt[myUid] = DateTime.now();
    _scheduleChatListSave(myUid);
    final controller = _privateChatsStreams[myUid];
    if (controller != null && !controller.isClosed) controller.add(list);
  }

  // ── Typing Indicator ──
  // Pakai realtime broadcast (ephemeral, tanpa tabel DB). Event 'typing'
  // dikirim ke channel per-chat; penerima hanya menampilkan kalau pengirimnya
  // bukan diri sendiri (broadcast ikut ter-echo ke pengirim).

  final Map<String, RealtimeChannel> _typingChannels = {};

  RealtimeChannel _typingChannel(String chatId) {
    return _typingChannels.putIfAbsent(chatId, () {
      final ch = _sb.channel('typing-$chatId');
      ch.subscribe();
      return ch;
    });
  }

  /// Stream event typing lawan bicara di satu chat.
  Stream<void> getTypingStream(String chatId) {
    final controller = StreamController<void>.broadcast();
    final channel = _typingChannel(chatId);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final senderId = payload['sender_id'] as String?;
        if (senderId == null || senderId == _sb.auth.currentUser?.id) return;
        if (!controller.isClosed) controller.add(null);
      },
    );
    controller.onCancel = () {
      _typingChannels.remove(chatId);
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Kirim sinyal typing (throttle dilakukan di screen).
  void sendTyping(String chatId) {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    _typingChannel(chatId)
        .sendBroadcastMessage(
          event: 'typing',
          payload: {
            'sender_id': uid,
            'ts': DateTime.now().millisecondsSinceEpoch,
          },
        )
        .catchError((_) => ChannelResponse.error);
  }

  void _refreshChatStreams(String myUid) {
    final callbacks = _chatReloaders[myUid];
    if (callbacks == null) return;
    for (final cb in List.of(callbacks)) {
      cb();
    }
  }

  /// Refresh paksa list private chat (dipanggil saat screen list di-mount
  /// ulang — broadcast stream tidak menyimpan data terakhir, jadi tanpa ini
  /// StreamBuilder bisa stuck spinner setelah tab di-switch).
  void refreshMyPrivateChats(String myUid) => _refreshChatStreams(myUid);

  void clearCachedStreams() {
    _chatReloaders.clear();
    for (final c in _privateChatsStreams.values) {
      if (!c.isClosed) c.close();
    }
    _privateChatsStreams.clear();
  }

  /// Fetch rows private_chats untuk user — dipakai getMyPrivateChats dan
  /// refresh saat stream cached di-subscribe ulang.
  Future<List<PrivateChatInfo>> _fetchPrivateChatRows(String myUid) async {
    final rows = await _sb
        .from('private_chats')
        .select()
        .contains('participants', [myUid])
        .order('last_message_at', ascending: false)
        .limit(50);
    Set<String> hiddenSet = {};
    try {
      hiddenSet = await getHiddenChats(myUid);
    } catch (e) {
      debugPrint('[ChatService] clearViewOnceImage ignored: $e');
    }
    _privateChatsHidden[myUid] = hiddenSet;
    return rows
        .where((row) => !hiddenSet.contains(row['chat_id']))
        .map(_rowToPrivateChat)
        .where((c) => c.messageCount > 0)
        .toList();
  }

  PrivateChatInfo _rowToPrivateChat(Map<String, dynamic> row) {
    final d = snakeToCamel(row);
    return PrivateChatInfo(
      chatId: d['chatId'] ?? '',
      participants: List<String>.from(d['participants'] ?? []),
      participantNames: Map<String, String>.from(d['participantNames'] ?? {}),
      participantGenders: Map<String, String>.from(
        d['participantGenders'] ?? {},
      ),
      participantLocations: Map<String, String>.from(
        d['participantLocations'] ?? {},
      ),
      participantAges: (d['participantAges'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      participantRegistered:
          (d['participantRegistered'] as Map<dynamic, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k.toString(), v == true),
          ),
      lastMessage: d['lastMessage'] ?? '',
      lastMessageAt: parseDate(d['lastMessageAt']),
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: (d['unreadCounts'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
      lastReadAt: (d['lastReadAt'] as Map<dynamic, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k.toString(), parseDate(v)),
      ),
    );
  }

  /// Snapshot terakhir list private chat — dipakai initialData StreamBuilder
  /// supaya tab Pesan tidak spinner saat di-mount ulang (broadcast stream
  /// tidak me-replay event yang di-add sebelum subscriber terpasang).
  List<PrivateChatInfo>? lastPrivateChatsSnapshot(String myUid) =>
      _privateChatsLast[myUid];

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    // Cache: kembali stream yang sudah ada agar channel Supabase
    // tidak dilipatgandakan tiap subscribe/didChange berikutnya.
    final existing = _privateChatsStreams[myUid];
    if (existing != null && !existing.isClosed) {
      // Subscriber baru (mis. balik ke sub-tab Pesan setelah buka Room):
      // broadcast stream tidak me-replay event lama, jadi kirim snapshot
      // terakhir dulu supaya list langsung tampil tanpa spinner.
      final last = _privateChatsLast[myUid];
      if (last != null) existing.add(last);
      // Snapshot sudah dijaga fresh oleh realtime (payload row lengkap) —
      // refetch 500 row cuma perlu kalau snapshot sudah lama / belum ada.
      final lastReload = _lastChatReloadAt[myUid];
      if (lastReload == null ||
          DateTime.now().difference(lastReload) > const Duration(seconds: 30)) {
        _refreshChatStreams(myUid);
      }
      return existing.stream;
    }

    final controller = StreamController<List<PrivateChatInfo>>.broadcast();
    _privateChatsStreams[myUid] = controller;

    Future<void> reload() async {
      try {
        final rows = await _fetchPrivateChatRows(myUid);
        _privateChatsLast[myUid] = rows;
        _lastChatReloadAt[myUid] = DateTime.now();
        debugPrint(
          '[getMyPrivateChats] fetched ${rows.length} chats for $myUid',
        );
        if (!controller.isClosed) controller.add(rows);
        if (rows.isNotEmpty) {
          MessageCache.instance
              .saveRawList(myUid, rows.map((c) => c.toMap()).toList());
        }
      } catch (e) {
        debugPrint('[getMyPrivateChats] fetch error for $myUid: $e');
      }
    }

    _chatReloaders.putIfAbsent(myUid, () => []).add(reload);

    // Cold start (app baru dibuka): tampilkan list dari cache disk DULU
    // tanpa spinner — fetch server menyusul dan mengkoreksi.
    MessageCache.instance.loadRawList(myUid).then((cachedRows) {
      if (cachedRows.isEmpty) return;
      final cached =
          cachedRows.map(PrivateChatInfo.fromMap).toList()
            ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      if (_privateChatsLast[myUid] != null &&
          _privateChatsLast[myUid]!.isNotEmpty) {
        return; // sudah ada data lebih baru — jangan timpa
      }
      _privateChatsLast[myUid] = cached;
      if (!controller.isClosed) controller.add(cached);
    });

    // Nama channel harus UNIK per instance — getMyPrivateChats bisa disubscribe
    // dari 2 screen sekaligus (list chat + layar chat); nama sama = join gagal,
    // event realtime tidak pernah sampai (centang baca jadi tidak update).
    final instanceId = DateTime.now().microsecondsSinceEpoch;
    final channel = _sb.channel('private-chats-$myUid-$instanceId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'private_chats',
      callback: (payload) {
        // Update snapshot langsung dari payload (row lengkap) — tanpa
        // refetch 500 row untuk setiap centang baca / pesan baru.
        if (controller.isClosed) return;
        if (payload.eventType == PostgresChangeEvent.delete) {
          final chatId = payload.oldRecord['chat_id'] as String?;
          if (chatId != null) _removeLocalChat(myUid, chatId);
        } else {
          _applyChatEvent(myUid, payload.newRecord);
        }
      },
    );
    channel.subscribe();

    // Pesan BARU masuk untuk chat yang aku hapus (hidden) → chat muncul lagi
    // di list, tapi hanya pesan setelah cutoff yang akan tampil isinya.
    // Chat yang tidak hidden tidak perlu dicek — row private_chats sudah
    // di-update trigger dan dikirim channel di atas (tanpa query tambahan).
    final msgChannel = _sb.channel('private-chats-msg-$myUid-$instanceId');
    msgChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'private_messages',
      callback: (payload) async {
        final chatId = payload.newRecord['chat_id'] as String?;
        if (chatId == null || controller.isClosed) return;
        if (!(_privateChatsHidden[myUid]?.contains(chatId) ?? false)) return;
        try {
          final row = await _sb
              .from('private_chats')
              .select('hidden_by,hidden_at')
              .eq('chat_id', chatId)
              .maybeSingle();
          if (row == null) return;
          final hidden = List<String>.from(
            (row['hidden_by'] as List<dynamic>?) ?? [],
          );
          if (!hidden.contains(myUid)) return;
          final hm = (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {};
          final cutoffStr = hm[myUid];
          final msgStr = payload.newRecord['created_at'] as String?;
          if (cutoffStr != null && msgStr != null) {
            final cutoff = DateTime.tryParse('$cutoffStr');
            final msgAt = DateTime.tryParse(msgStr);
            if (cutoff == null || msgAt == null || !msgAt.isAfter(cutoff))
              return;
          }
          await unhideChat(myUid, chatId);
          // Row private_chats berubah → channel di atas yang apply ke list.
        } catch (e) {
          debugPrint('[ChatService] clearViewOnceImage ignored: $e');
        }
      },
    );
    msgChannel.subscribe();

    reload();

    controller.onCancel = () {
      _chatReloaders[myUid]?.remove(reload);
      if (_chatReloaders[myUid]?.isEmpty == true) _chatReloaders.remove(myUid);
      _sb.removeChannel(channel);
      _sb.removeChannel(msgChannel);
      final cached = _privateChatsStreams[myUid];
      if (cached == controller) {
        _privateChatsStreams.remove(myUid);
        _privateChatsLast.remove(myUid);
        _privateChatsHidden.remove(myUid);
        _lastChatReloadAt.remove(myUid);
      }
    };

    return controller.stream;
  }

  /// Hitung status efektif: last_seen basi (> 30 menit) dianggap offline.
  /// Status 'invisible' (admin) dianggap offline bagi user lain.
  /// Dipakai getUserStatus & UserInfoScreen agar logikanya seragam.
  static String effectiveStatusOf(String? rawStatus, String? lastSeenStr) {
    final s = rawStatus ?? 'offline';
    if (s == 'offline' || s == 'invisible') return 'offline';
    final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
    if (lastSeen == null) return 'offline';
    final stale = lastSeen.toUtc().isBefore(
      DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    );
    return stale ? 'offline' : s;
  }

  /// Stream status realtime satu user (online/idle/offline).
  /// Pakai channel postgres changes pada profiles — ringan, hanya 1 row.
  /// Status dihitung efektif: last_seen basi (> 15 menit) dianggap offline,
  /// supaya sinkron dengan daftar pengguna online di list chat.
  /// [initialStatus] membuat stream langsung emit status yang sudah diketahui
  /// (misal dari profil yang baru di-fetch) tanpa query DB tambahan.
  Stream<String> getUserStatus(String uid, {String? initialStatus}) {
    final controller = StreamController<String>.broadcast();
    String _current = initialStatus ?? 'offline';
    if (initialStatus != null && initialStatus != 'offline') {
      Future.microtask(() {
        if (!controller.isClosed) controller.add(_current);
      });
    }

    Future<void> fetchStatus() async {
      try {
        final row = await _sb
            .from('profiles')
            .select('status,last_seen')
            .eq('id', uid)
            .maybeSingle();
        if (row == null || controller.isClosed) return;
        final s = ChatService.effectiveStatusOf(
          row['status'] as String?,
          row['last_seen'] as String?,
        );
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      } catch (e) {
        debugPrint('[chat] fetchStatus error: $e');
      }
    }

    final channel = _sb.channel('user-status-$uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: uid,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final s = ChatService.effectiveStatusOf(
          payload.newRecord['status'] as String?,
          payload.newRecord['last_seen'] as String?,
        );
        if (s != _current) {
          _current = s;
          controller.add(_current);
        }
      },
    );
    channel.subscribe();
    if (initialStatus == null) fetchStatus();

    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsers() {
    final controller = StreamController<List<UserModel>>.broadcast();
    List<UserModel> cached = [];
    Timer? debounce;

    Future<void> syncFromPresence() async {
      try {
        final state = RealtimeHub.instance.onlinePresenceState;
        // Coba RPC ringan dulu (1 RTT, server-side, tanpa IN 500)
        List<dynamic> rpcRows = [];
        bool usedRpc = false;
        try {
          final data = await _sb.rpc('get_online_users', params: {'p_limit': 100}).timeout(const Duration(seconds: 4));
          if (data is List && data.isNotEmpty) {
            rpcRows = data;
            usedRpc = true;
          }
        } catch (_) {}
        List<dynamic> rows;
        if (usedRpc) {
          rows = rpcRows;
        } else {
          // Fallback hybrid lama jika RPC belum deploy / gagal
          final presenceUids = state.values.expand((list) => list).map((m) => '${m['uid'] ?? ''}').where((id) => id.isNotEmpty).toList();
          Set<String> dbUids = {};
          try {
            final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String();
            final dbRows = await _sb.from('profiles').select('id').neq('status', 'offline').neq('status', 'invisible').gte('last_seen', cutoff).limit(100).timeout(const Duration(seconds: 4));
            for (final r in dbRows) {
              final id = '${r['id'] ?? ''}';
              if (id.isNotEmpty) dbUids.add(id);
            }
          } catch (_) {}
          final uids = {...presenceUids, ...dbUids}.toList();
          if (uids.isEmpty) {
            cached = [];
            if (!controller.isClosed) controller.add(List.unmodifiable(cached));
            return;
          }
          String? invisibleUid2;
          try {
            final setting = await _sb.from('app_settings').select('invisible_enabled,invisible_admin_uid').eq('id', 'global').maybeSingle().timeout(const Duration(seconds: 3));
            if (setting?['invisible_enabled'] == true) invisibleUid2 = setting?['invisible_admin_uid'] as String?;
          } catch (_) {}
          final filtered2 = invisibleUid2 == null ? uids : uids.where((id) => id != invisibleUid2).toList();
          if (filtered2.isEmpty) {
            cached = [];
            if (!controller.isClosed) controller.add(List.unmodifiable(cached));
            return;
          }
          const cols2 = 'id,nickname,gender,age,country,city,status,avatar,is_registered,last_seen';
          rows = await _sb.from('profiles').select(cols2).inFilter('id', filtered2).limit(1000).timeout(const Duration(seconds: 6));
        }
        // Invisible filter untuk path RPC juga
        String? invisibleUid;
        try {
          final setting = await _sb.from('app_settings').select('invisible_enabled,invisible_admin_uid').eq('id', 'global').maybeSingle().timeout(const Duration(seconds: 2));
          if (setting?['invisible_enabled'] == true) invisibleUid = setting?['invisible_admin_uid'] as String?;
        } catch (_) {}
        if (invisibleUid != null) {
          rows = rows.where((r) => '${(r as Map)['id']}' != invisibleUid).toList();
        }
        final seen = <String>{};
        final pending = <UserModel>[];
        for (final row in rows) {
          try {
            final u = UserModel.fromMap('${row['id']}', snakeToCamel(row));
            if (!seen.add(u.uid)) continue;
            pending.add(u);
          } catch (e) {
            debugPrint('[getOnlineUsers] skip bad row: $e');
          }
        }
        // Progressive: emit dulu tanpa avatar (instant), avatar nyusul background
        cached = List.of(pending);
        if (!controller.isClosed) controller.add(List.unmodifiable(cached));
        // Background download avatar batch 20
        const avatarBatch = 20;
        bool avatarUpdated = false;
        for (var i = 0; i < pending.length; i += avatarBatch) {
          final chunk = pending.skip(i).take(avatarBatch).toList();
          final results = await Future.wait(chunk.map((u) async {
            if (u.avatar.isNotEmpty && StoragePhotoService.instance.isAvatarPath(u.avatar)) {
              final b64 = await _avatarB64(u.avatar);
              if (b64.isNotEmpty) return u.copyWith(avatar: b64);
            }
            return u;
          }));
          for (var j = 0; j < chunk.length; j++) {
            final idx = cached.indexWhere((c) => c.uid == chunk[j].uid);
            if (idx >= 0 && results[j].avatar != cached[idx].avatar) {
              cached[idx] = results[j];
              avatarUpdated = true;
            }
          }
        }
        if (avatarUpdated && !controller.isClosed) controller.add(List.unmodifiable(cached));
      } catch (e) {
        debugPrint('[getOnlineUsers] presence fetch error: $e');
        if (!controller.isClosed) controller.addError(e);
      }
    }

    final sub = RealtimeHub.instance.onlinePresence.listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 300), syncFromPresence);
    });
    // initial sync
    syncFromPresence();
    // also periodic fallback if presence empty (cold start before track)
    final fallbackTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (cached.isEmpty) syncFromPresence();
    });
    controller.onCancel = () {
      debounce?.cancel();
      fallbackTimer.cancel();
      sub.cancel();
    };
    return controller.stream;
  }

  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', roomId)
        .map((rows) {
          // Presensi basi (joined_at > 5 menit, heartbeat 60 detik tidak jalan
          // lagi karena app di-kill/background) dianggap sudah keluar room.
          final cutoff = DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          );
          return rows
              .where((row) {
                final joined = DateTime.tryParse('${row['joined_at']}');
                return joined != null && joined.toUtc().isAfter(cutoff);
              })
              .map((row) {
                final d = snakeToCamel(row);
                return UserModel(
                  uid: d['userId'] ?? '',
                  nickname: d['nickname'] ?? 'Anon',
                  gender: d['gender'] ?? 'other',
                  age: (d['age'] as num?)?.toInt() ?? 0,
                  country: d['country'] ?? '',
                  city: d['city'] ?? '',
                  ipAddress: '',
                  status: 'online',
                  avatar: '',
                  isRegistered: d['isRegistered'] == true,
                  loginAt: DateTime.now(),
                  createdAt: DateTime.now(),
                  lastSeen: parseDate(d['joinedAt']),
                );
              })
              .toList();
        });
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    // nickname, gender, age di-set oleh trigger DB dari profiles
    // tidak dikirim dari client untuk mencegah impersonasi
    // joined_at di-refresh setiap heartbeat (60 detik) — row presence
    // yang basi (app di-kill/force-stop) otomatis difilter dari daftar
    // online room oleh getOnlineUsersInRoom / getRoomOnlineCounts.
    await _sb.from('room_presence').upsert({
      'room_id': roomId,
      'user_id': user.uid,
      'joined_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'room_id,user_id');
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _sb
        .from('room_presence')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', uid);
  }

  // ── Hide Chat (soft-delete via server) ──
  // Chat ditandai hidden_by + hidden_at (cutoff) di DB, tidak dihapus.
  // Lawan bicara tetap melihat chat normal (tanpa cutoff).
  // History sebelum cutoff tidak pernah tampil lagi untuk user yang menghapus;
  // hanya pesan BARU setelah cutoff yang muncul saat chat terbuka lagi.

  Future<void> hideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by,hidden_at')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    final hiddenAt = Map<String, dynamic>.from(
      (row['hidden_at'] as Map<dynamic, dynamic>?) ?? {},
    );
    if (!hidden.contains(myUid)) hidden.add(myUid);
    // Cutoff selalu di-refresh — pesan sebelum waktu delete terbaru
    // tetap tidak tampil walau chat sudah pernah muncul lagi sebelumnya.
    hiddenAt[myUid] = DateTime.now().toUtc().toIso8601String();
    await _sb
        .from('private_chats')
        .update({'hidden_by': hidden, 'hidden_at': hiddenAt})
        .eq('chat_id', chatId);
  }

  Future<void> unhideChat(String myUid, String chatId) async {
    final row = await _sb
        .from('private_chats')
        .select('hidden_by')
        .eq('chat_id', chatId)
        .maybeSingle();
    if (row == null) return;
    final hidden = List<String>.from(
      (row['hidden_by'] as List<dynamic>?) ?? [],
    );
    if (hidden.remove(myUid)) {
      await _sb
          .from('private_chats')
          .update({'hidden_by': hidden})
          .eq('chat_id', chatId);
    }
  }

  Future<Set<String>> getHiddenChats(String myUid) async {
    try {
      final rows = await _sb.from('private_chats').select('chat_id').contains(
        'hidden_by',
        [myUid],
      );
      return rows.map((r) => r['chat_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Stream<Map<String, int>> getRoomOnlineCounts() {
    return _sb
        .from('room_presence')
        .stream(primaryKey: ['room_id', 'user_id'])
        .map((rows) {
          final counts = <String, int>{};
          // Sama seperti daftar user room: presence basi (> 5 menit) tidak
          // dihitung supaya count online di lobby tidak ghost.
          final cutoff = DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          );
          for (final row in rows) {
            final joined = DateTime.tryParse('${row['joined_at']}');
            if (joined == null || !joined.toUtc().isAfter(cutoff)) continue;
            final roomId = '${row['room_id']}';
            counts[roomId] = (counts[roomId] ?? 0) + 1;
          }
          return counts;
        });
  }

  // ── Block / Report ──

  Future<void> blockUser(String myUid, String blockedUid) async {
    await _sb.from('blocks').upsert({
      'blocker_id': myUid,
      'blocked_id': blockedUid,
    }, onConflict: 'blocker_id,blocked_id');
  }

  Future<void> unblockUser(String myUid, String blockedUid) async {
    await _sb
        .from('blocks')
        .delete()
        .eq('blocker_id', myUid)
        .eq('blocked_id', blockedUid);
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
  }) async {
    await _sb.from('reports').insert({
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason,
    });
  }

  Future<bool> isUserBlocked(String myUid, String otherUid) async {
    final res = await _sb
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', myUid)
        .eq('blocked_id', otherUid)
        .maybeSingle();
    return res != null;
  }

  Future<List<String>> getBlockedUids(String myUid) async {
    final res = await _sb
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', myUid);
    return res.map((r) => '${r['blocked_id']}').toList();
  }
}

class PrivateChatInfo {
  final String chatId;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantGenders;
  final Map<String, String> participantLocations;
  final Map<String, int> participantAges;
  final Map<String, bool> participantRegistered;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int messageCount;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> lastReadAt;

  PrivateChatInfo({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    this.participantGenders = const {},
    this.participantLocations = const {},
    this.participantAges = const {},
    this.participantRegistered = const {},
    required this.lastMessage,
    required this.lastMessageAt,
    this.messageCount = 0,
    this.unreadCounts = const {},
    this.lastReadAt = const {},
  });

  Map<String, dynamic> toMap() => {
    'chatId': chatId,
    'participants': participants,
    'participantNames': participantNames,
    'participantGenders': participantGenders,
    'participantLocations': participantLocations,
    'participantAges': participantAges,
    'participantRegistered': participantRegistered,
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt.toIso8601String(),
    'messageCount': messageCount,
    'unreadCounts': unreadCounts,
    'lastReadAt': lastReadAt.map((k, v) => MapEntry(k, v.toIso8601String())),
  };

  static Map<String, String> _strMap(dynamic v) =>
      ((v as Map?) ?? {}).map((k, e) => MapEntry('$k', '$e'));

  factory PrivateChatInfo.fromMap(Map<String, dynamic> d) {
    return PrivateChatInfo(
      chatId: '${d['chatId'] ?? ''}',
      participants: List<String>.from(d['participants'] ?? const []),
      participantNames: _strMap(d['participantNames']),
      participantGenders: _strMap(d['participantGenders']),
      participantLocations: _strMap(d['participantLocations']),
      participantAges: ((d['participantAges'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      participantRegistered: ((d['participantRegistered'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', v == true),
      ),
      lastMessage: '${d['lastMessage'] ?? ''}',
      lastMessageAt:
          DateTime.tryParse('${d['lastMessageAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
      unreadCounts: ((d['unreadCounts'] as Map?) ?? {}).map(
        (k, v) => MapEntry('$k', (v as num).toInt()),
      ),
      lastReadAt: ((d['lastReadAt'] as Map?) ?? {}).map(
        (k, v) =>
            MapEntry('$k', DateTime.tryParse('$v') ?? DateTime(2000)),
      ),
    );
  }

  PrivateChatInfo copyWith({
    String? chatId,
    List<String>? participants,
    Map<String, String>? participantNames,
    Map<String, String>? participantGenders,
    Map<String, String>? participantLocations,
    Map<String, int>? participantAges,
    Map<String, bool>? participantRegistered,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? messageCount,
    Map<String, int>? unreadCounts,
    Map<String, DateTime>? lastReadAt,
  }) {
    return PrivateChatInfo(
      chatId: chatId ?? this.chatId,
      participants: participants ?? this.participants,
      participantNames: participantNames ?? this.participantNames,
      participantGenders: participantGenders ?? this.participantGenders,
      participantLocations: participantLocations ?? this.participantLocations,
      participantAges: participantAges ?? this.participantAges,
      participantRegistered:
          participantRegistered ?? this.participantRegistered,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messageCount: messageCount ?? this.messageCount,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }
}
