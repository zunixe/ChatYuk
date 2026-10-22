import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message_model.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../utils.dart';
import '../core/media/native_image.dart';
import '../core/photo_quality_pref.dart';
import '../core/cache/offline_outbox.dart';
import '../core/cache/photo_cache.dart';
import '../core/storage_paths.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/gallery_picker_sheet.dart';
import '../widgets/message/image_decode_core.dart' show warmPhotoCacheForPath;
import '../widgets/message/view_once_state.dart' show migrateViewOnceState;
import '../widgets/video_prefetch.dart';
import 'chat_outbox_mixin.dart';

/// Modul BERSAMA kirim foto & view-once (private ↔ room).
///
/// Dulu logika ini hidup dua kali: private sudah pakai optimistic + antrean
/// offline; room masih 79 baris mandiri TANPA outbox. Sekarang satu jalur —
/// room ikut dapat centang-1 + kirim otomatis saat koneksi pulih.
///
/// Acuan = `private_chat_screen`. Perbedaan produk dijaga lewat hook
/// ([photoDispatch] beda private/room, [photoFirstBonus] hanya private).
///
/// Wajib dipakai bersama [ChatOutboxMixin].

/// Routing timer preview → kind efektif. Murni & testable.
/// Timer apa pun (0/3/10) memaksa view-once; null = kind asal.
/// Satu dispatch per kirim dijamin pemanggil ([_sendImageLike] satu jalur).
String resolvePhotoSendKind(String kind, int? viewSecs) =>
    viewSecs != null ? 'view_once' : kind;

/// Type pesan video: 'video_once' bila "sekali lihat" dipilih, else 'video'.
/// Murni & testable — dipakai optimistic bubble DAN dispatch server supaya
/// keduanya konsisten (dulu optimistic selalu 'video' & dispatch membaca
/// flag setelah preview dibersihkan → video sekali-lihat terkirim biasa).
String videoSendType(bool isOnce) => isOnce ? 'video_once' : 'video';
mixin ChatPhotoSendMixin<T extends StatefulWidget> on ChatOutboxMixin<T> {
  // ── Kontrak ──
  /// Kirim pesan gambar (private: sendPrivateMessage; room: sendRoomMessage).
  /// [viewOnceSecs]: durasi view-once detik (0 = sampai ditutup);
  /// null = bukan view-once timer / legacy.
  Future<String?> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
    String text = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    /// Metadata kutipan (jenis media + dimensi + path video) → thumbnail di
    /// kutipan balasan. Null = kutipan teks saja (perilaku lama).
    Map<String, dynamic>? repliedToMeta,
    int? viewOnceSecs,
    /// Durasi VIDEO (ms) untuk bubble + validasi server. Null = bukan video.
    int? videoDurationMs,
    /// Path storage poster video (JPEG) — preview penerima. '' = tanpa poster.
    String videoPoster = '',
    /// Album foto: semua foto batch berbagi id yang sama.
    String? albumId,
  });

  /// Timer view-once yang dipilih di preview (detik; null = foto normal).
  /// Hanya private screen yang mengisi — room default null (tak berubah).
  int? get photoViewTimerSecs => null;

  /// Reset pilihan timer setelah preview terkirim/dibatalkan.
  void photoClearViewTimer() {}

  /// Folder upload storage (private: chatId; room: `room_<id>`).
  String get photoUploadChatId;

  /// chatKey untuk `PhotoCache` (private: `private_<chatId>`; room: `room_<id>`).
  /// Default `private_<uploadChatId>`; room meng-override.
  String get photoCacheChatKey => 'private_$photoUploadChatId';

  /// Seed watermark view-once (private: uid lawan; room: id room).
  String get photoSeed;

  /// Efek setelah foto sukses terkirim (private: bonus + fallback; room: no-op).
  void photoOnSent(String kind);

  /// Bonus sekali pakai khusus private (`first_photo`); room = no-op.
  void photoFirstBonus(PointsNotifier pp);

  /// Set preview foto di composer (private: + fokus & scroll; room: set saja).
  void photoSetPreview(String base64);

  /// Set preview VIDEO di composer (poster + durasi).
  /// Default no-op — di-override oleh private chat DAN room (video room sudah
  /// aktif sejak paritas media 2026-10-21; lihat `room_chat_core.dart`).
  void videoSetPreview({
    required String path,
    required String posterBase64,
    required int durationMs,
  }) {}

  /// Buang preview video (batal/kirim). Room default no-op.
  void videoClearPreview() {}

  /// Path video yang sedang di-preview (null = tidak ada). Room selalu null.
  String? get pendingVideoPath => null;

  /// True bila fitur video aktif di layar ini. Default false; private chat &
  /// room meng-override jadi true.
  bool get videoSendEnabled => false;

  /// Video dikirim sebagai "sekali lihat"? (private: toggle di preview).
  /// Room: false. Berbeda dari foto — video TIDAK punya timer detik karena
  /// `duration_ms` sudah dipakai untuk panjang video (playback).
  bool get videoOnceSelected => false;

  /// Set status sekali-lihat video. Room: no-op.
  void videoSetOnce(bool value) {}

  /// Teks caption yang sedang diketik di composer (view-once picker mengirim
  /// langsung, jadi harus menangkap teks SAAT INI). Default kosong.
  String get photoComposerText => '';

  /// Balasan yang sedang aktif (untuk view-once). Default null.
  MessageModel? get photoReplyingTo => null;

  /// Bersihkan composer + status balas setelah view-once terkirim.
  void photoClearComposerText() {}

  final ImagePicker _photoPicker = ImagePicker();

  ImagePicker get photoPicker => _photoPicker;

  /// Bytes ASLI foto yang sedang di-preview (untuk proses ulang HD).
  /// Null = tidak ada preview / preview dibatalkan / sudah terkirim.
  Uint8List? pendingPhotoOriginal;

  /// Toggle HD di preview (default dari setting). Reset tiap buka preview.
  bool photoHd = false;

  /// Buka preview: simpan original + default HD dari setting.
  Future<void> _openPreview(Uint8List original, String? processed) async {
    pendingPhotoOriginal = original;
    photoHd = await PhotoQualityPref.defaultHd;
    if (processed != null && mounted) photoSetPreview(processed);
    if (processed == null) {
      pendingPhotoOriginal = null;
      photoHd = false;
    }
  }

  /// Buang state preview (dipanggil saat batal/kirim).
  void photoClearPreviewState() {
    pendingPhotoOriginal = null;
    photoHd = false;
  }

  /// Tombol kamera: ambil → proses → taruh di preview composer.
  Future<void> photoTakeToPreview() async {
    final picked = await _photoPicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final processed = await photoProcess(bytes);
    await _openPreview(bytes, processed);
  }

  /// Tombol galeri: ambil SATU atau BANYAK foto (maks 10) → preview →
  /// kirim sebagai satu ALBUM (bundle ala WhatsApp). Batch berbagi
  /// `albumId`; caption ditempel di foto terakhir. HD berlaku ke semua.
  static const int _maxAlbumPhotos = 10;

  /// Foto-foto tambahan batch (base64 terproses) — foto pertama tetap di
  /// jalur preview lama (`_openPreview`).
  final List<String> albumExtraB64 = [];
  final List<Uint8List> albumExtraOriginal = [];

  Future<void> photoPickFromGalleryToPreview() async {
    List<XFile> picked;
    try {
      picked = await _photoPicker.pickMultiImage(
        limit: _maxAlbumPhotos,
        imageQuality: 92,
      );
    } catch (_) {
      // Plugin lama tanpa `limit` → jatuh ke pilih tunggal.
      final one = await _photoPicker.pickImage(source: ImageSource.gallery);
      if (one == null) return;
      picked = [one];
    }
    if (picked.isEmpty) return;
    albumExtraB64.clear();
    albumExtraOriginal.clear();

    Uint8List? firstBytes;
    String? firstProcessed;
    for (var i = 0; i < picked.length; i++) {
      final bytes = await picked[i].readAsBytes();
      final processed = await photoProcess(bytes);
      if (processed == null) continue; // gagal satu → lewati, sisanya lanjut
      if (firstProcessed == null) {
        firstBytes = bytes;
        firstProcessed = processed;
      } else {
        albumExtraB64.add(processed);
        albumExtraOriginal.add(bytes);
      }
    }
    if (firstProcessed == null) return;
    await _openPreview(firstBytes!, firstProcessed);
  }

  /// Validasi ukuran + resize isolate. Return base64, null bila gagal
  /// (pesan error sudah tampil).
  Future<String?> photoProcess(Uint8List bytes) async {
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
        showChatSnack(context, s.msgFileTooLarge);
      }
      return null;
    }
    final base64 = await NativeImage.processJpeg(bytes);
    if (base64 == null && mounted) {
      final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      showChatSnack(context, s.errPhotoRead);
    }
    return base64;
  }

  /// Status toggle HD yang dipilih di panel galeri saat memilih foto
  /// sekali-lihat (default false). Dibaca `processViewOnceBytes` supaya
  /// foto terkirim HD saat togglenya aktif — minta user 2026-10-19: "ada HD
  /// nya disamping kanan" seperti pada pemilih foto biasa.
  bool viewOncePickHd = false;

  /// Ambil bytes gambar untuk view-once.
  ///
  /// Minta user (2026-10-19): pemilihnya harus panel galeri yang SLIDE DARI
  /// BAWAH dengan judul "Terbaru" + toggle HD di kanan — SAMA seperti saat
  /// kirim foto biasa (`GalleryPickerSheet`), bukan membuka aplikasi galeri
  /// HP lewat `image_picker`. `maxSelect: 1` karena sekali-lihat = 1 foto.
  ///
  /// Fallback: bila plugin galeri tidak tersedia/gagal (mis. di test),
  /// kembali ke `image_picker` supaya alur kirim tidak mati.
  Future<Uint8List?> pickViewOnceImage() async {
    if (mounted) {
      final s = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(localeProvider).s;
      try {
        final res = await GalleryPickerSheet.show(
          context,
          s: s,
          maxSelect: 1,
        );
        if (res == null) return null;
        if (res.useSystemPicker) {
          // Tombol folder → pemilih sistem (perilaku lama).
          final picked = await _photoPicker.pickImage(
            source: ImageSource.gallery,
          );
          if (picked == null) return null;
          return await picked.readAsBytes();
        }
        // HD dipilih di sheet → diteruskan ke pemrosesan (lihat
        // `sendViewOnceFromPicker` → `processViewOnceBytes`).
        viewOncePickHd = res.hd;
        final bytes = await res.readBytes();
        return bytes.isEmpty ? null : bytes.first;
      } catch (_) {
        // Plugin galeri tak tersedia → jatuh ke image_picker di bawah.
      }
    }
    final picked = await _photoPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// Proses bytes → base64 (watermark view-once bila aktif). Di-override di
  /// test supaya alur caption diuji tanpa `compute()` (isolate di test-fake
  /// bisa menggantung).
  ///
  /// HD: bila toggle HD di panel galeri aktif (`viewOncePickHd`), resolusi
  /// dinaikkan (1920px / q90) — sama seperti jalur foto biasa.
  Future<String?> processViewOnceBytes(Uint8List bytes) async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (viewOncePickHd) {
      return auth.watermarkEnabled
          ? NativeImage.processViewOnce(bytes, photoSeed)
          : NativeImage.processJpeg(bytes, maxPx: 1920, quality: 90);
    }
    return auth.watermarkEnabled
        ? NativeImage.processViewOnce(bytes, photoSeed)
        : NativeImage.processJpeg(bytes, maxPx: 1200, quality: 82);
  }

  /// Kirim view-once (watermark bila aktif).
  ///
  /// View-once dari picker mengirim LANGSUNG (tanpa preview), jadi caption
  /// harus ditangkap dari composer SAAT INI (dulu caption diabaikan → teks
  /// yang diketik hilang saat kirim foto sekali-lihat).
  Future<void> sendViewOnceFromPicker() async {
    // Tangkap caption & balasan SEBELUM buka galeri (picker async; teks user
    // saat menekan "sekali lihat" yang dipakai).
    final caption = capitalizeFirst(photoComposerText.trim());
    final reply = photoReplyingTo;
    final bytes = await pickViewOnceImage();
    if (bytes == null) return;
    if (!mounted) return;
    final base64 = await processViewOnceBytes(bytes);
    if (base64 == null) {
      if (mounted) {
        final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
        showChatSnack(context, s.errPhotoRead);
      }
      return;
    }
    if (!mounted) return;
    // Bersihkan composer lebih dulu supaya teks tidak tertinggal/dobel.
    if (caption.isNotEmpty || reply != null) photoClearComposerText();
    await _sendImageLike(
      base64: base64,
      kind: 'view_once',
      type: 'view_once',
      text: caption,
      reply: reply,
    );
  }

  // ── VIDEO (private chat) ──
  /// Progress kompres 0..1 (null = tidak sedang kompres) — untuk UI.
  double? videoCompressProgress;

  /// Pilih video dari galeri → validasi durasi → kompres 480p → preview.
  /// Return true bila preview siap. Pesan error sudah tampil bila gagal.
  Future<bool> videoPickToPreview() async {
    if (!videoSendEnabled) return false;
    void toast(String msg) {
      if (!mounted) return;
      showChatSnack(context, msg);
    }

    XFile? picked;
    try {
      picked = await _photoPicker.pickVideo(source: ImageSource.gallery);
    } catch (e) {
      dlog('[Video] pick error: $e');
      return false;
    }
    if (picked == null) return false;
    if (!mounted) return false;
    return _processPickedVideo(picked.path, toast: toast);
  }

  /// Rekam video via KAMERA SISTEM (image_picker) → proses → preview.
  /// Batas 60 dtk (kamera sistem menghentikan otomatis + validasi ulang).
  /// Dipilih dari toggle FOTO|VIDEO di composer.
  Future<bool> videoRecordFromCamera() async {
    if (!videoSendEnabled) return false;
    void toast(String msg) {
      if (!mounted) return;
      showChatSnack(context, msg);
    }

    XFile? picked;
    try {
      picked = await _photoPicker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(seconds: 60),
      );
    } catch (e) {
      dlog('[Video] record error: $e');
      return false;
    }
    if (picked == null) return false;
    if (!mounted) return false;
    return _processPickedVideo(picked.path, toast: toast);
  }

  /// Proses FOTO dari file (hasil jepret kamera in-app) → resize → preview.
  Future<void> photoFromFileToPreview(Uint8List bytes) async {
    final processed = await photoProcess(bytes);
    if (!mounted) return;
    await _openPreview(bytes, processed);
  }

  /// Proses video dari FILE (hasil rekam kamera in-app) → kompres → preview.
  Future<bool> videoFromFileToPreview(String path) async {
    if (!videoSendEnabled) return false;
    if (!mounted) return false;
    void toast(String msg) {
      if (!mounted) return;
      showChatSnack(context, msg);
    }

    return _processPickedVideo(path, toast: toast);
  }

  /// Kompres + poster + preview dari path video (dipakai galeri & rekam).
  /// Validasi durasi (>60 dtk ditolak) dan ukuran hasil.
  Future<bool> _processPickedVideo(
    String path, {
    required void Function(String) toast,
  }) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final storage = ProviderScope.containerOf(context, listen: false).read(storageProvider);
    // 1) Cek durasi ASLI sebelum kompres (tolak >60 dtk lebih awal —
    //    jangan buang waktu kompres video 5 menit).
    final rawMs = await storage.videoDurationMs(path);
    if (!mounted) return false;
    if (rawMs > 0 && rawMs > chatVideoMaxMsValue) {
      toast(s.videoTooLong);
      return false;
    }

    // 2) Kompres (progress ditampilkan di composer).
    setState(() => videoCompressProgress = 0);
    File? out;
    try {
      out = await storage.compressChatVideo(
        path,
        onProgress: (p) {
          if (mounted) setState(() => videoCompressProgress = p);
        },
      );
    } finally {
      if (mounted) setState(() => videoCompressProgress = null);
    }
    if (!mounted) return false;
    if (out == null || !await out.exists()) {
      toast(s.videoCompressFail);
      return false;
    }

    // 3) Batas ukuran hasil.
    final bytes = await out.readAsBytes();
    if (bytes.length > chatVideoMaxBytesValue) {
      toast(s.videoTooLarge);
      return false;
    }

    // 4) Durasi hasil (untuk label + batas server) + poster thumbnail.
    var outMs = await storage.videoDurationMs(out.path);
    if (outMs <= 0) outMs = rawMs;
    if (outMs <= 0) outMs = 1000;
    final poster = await storage.storyVideoPoster(out.path);
    if (!mounted) return false;
    if (poster == null || poster.isEmpty) {
      toast(s.videoCompressFail);
      return false;
    }

    videoSetPreview(
      path: out.path,
      posterBase64: base64Encode(poster),
      durationMs: outMs,
    );
    return true;
  }

  /// Kirim video dari preview (upload → dispatch type 'video').
  ///
  /// Nama TIDAK boleh sama dengan kontrak publik di `ChatSendMixin`
  /// (`sendVideoFromPreview`): implementasi di mixin ini akan MENANG atas
  /// override layar karena urutan linearisasi mixin → video tak terkirim.
  /// Kontrak publik tetap `sendVideoFromPreview` (lihat ChatSendMixin);
  /// layar meng-override-nya dan memanggil `sendVideoFromPreviewImpl`.
  Future<void> sendVideoFromPreviewImpl({
    String text = '',
    MessageModel? reply,
  }) async {
    final path = pendingVideoPath;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final durationMs = pendingVideoMs;
    // Tangkap "sekali lihat" SEBELUM clear preview: videoClearPreview()
    // me-reset _pendingVideoOnce=false → kalau dibaca setelah clear, video
    // sekali-lihat selalu terkirim sebagai video biasa (bug: type='video').
    final isOnce = videoOnceSelected;
    // POSTER juga WAJIB ditangkap SEBELUM clear — videoClearPreview men-null-kan
    // _pendingVideoPoster → dulu poster selalu null saat kirim (thumbnail
    // penerima tak pernah ada). Sama pola dengan isOnce di atas.
    final posterB64 = pendingVideoPosterB64;
    videoClearPreview();

    final file = File(path);
    final bytes = await file.exists() ? await file.readAsBytes() : null;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        showChatSnack(context, s.videoCompressFail);
      }
      return;
    }
    await _sendVideoLike(
      bytes: bytes,
      durationMs: durationMs,
      text: text,
      reply: reply,
      isOnce: isOnce,
      posterB64: posterB64,
    );
  }

  /// Durasi video preview (ms). WAJIB getter (bukan field) supaya layar
  /// bisa meng-override dengan state-nya — field di mixin akan MENUTUPI
  /// getter layar dan selalu bernilai 0 (durasi hilang saat kirim).
  int get pendingVideoMs => 0;

  /// Poster video preview (base64) — layar meng-override dengan state-nya.
  /// Dipakai untuk hangatkan poster ke disk TANPA unduh ulang server.
  String? get pendingVideoPosterB64 => null;

  /// Jalur kirim video: optimistic bubble → poin → upload → dispatch.
  /// Tanpa view-once (video tidak punya mode sekali lihat).
  Future<void> _sendVideoLike({
    required Uint8List bytes,
    required int durationMs,
    String text = '',
    MessageModel? reply,
    bool isOnce = false,
    String? posterB64,
  }) async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;

    // Preview lokal (base64 data-uri) supaya bubble langsung tampil —
    // path storage baru ada setelah upload.
    final pendingVideo = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: text,
      type: videoSendType(isOnce),
      imageData: base64Encode(bytes),
      timestamp: DateTime.now(),
      durationMs: durationMs,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
    );
    setState(() => outboxPending.add(pendingVideo));
    outboxScrollToBottom();

    // Offline: antre (upload menyusul saat online).
    if (!outboxIsOnline) {
      await queueOffline(
        pending: pendingVideo,
        pointsKind: 'image',
        pointsDeducted: false,
        imagePayload: base64Encode(bytes),
        needsUpload: true,
        uploadKind: 'video',
        durationMs: durationMs,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
        videoPosterB64: pendingVideoPosterB64 ?? '',
      );
      return;
    }

    final pp = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
    // Biaya kirim video = sama dengan foto (kind 'image').
    final r = await pp.deductBeforeSend('image');
    if (r < 0) {
      if (r == -2) {
        await queueOffline(
          pending: pendingVideo,
          pointsKind: 'image',
          pointsDeducted: false,
          imagePayload: base64Encode(bytes),
          needsUpload: true,
          uploadKind: 'video',
          durationMs: durationMs,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
          videoPosterB64: pendingVideoPosterB64 ?? '',
        );
        return;
      }
      setState(
        () => outboxPending.removeWhere((m) => m.id == pendingVideo.id),
      );
      if (!mounted) return;
      if (r == -1) {
        pp.showOutOfPointsDialog(context, s.isId);
      } else {
        showChatSnack(context, s.errSendPhoto);
      }
      return;
    }

    try {
      final path = await ProviderScope.containerOf(context, listen: false).read(storageProvider).uploadChatVideo(
        chatId: photoUploadChatId,
        bytes: bytes,
      );
      if (path == null || path.isEmpty) {
        if (!outboxIsOnline) {
          throw const SocketException('video upload failed');
        }
        safeUnawaited(pp.refundChatPoint('image'));
        if (mounted) {
          showChatSnack(context, s.errSendPhoto);
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingVideo.id),
          );
        }
        return;
      }
      // "Sekali lihat" video ditandai lewat TYPE (video_once) — bukan
      // durationMs yang sudah dipakai untuk panjang video. Nilai `isOnce`
      // ditangkap pemanggil SEBELUM preview dibersihkan.
      // Poster + video hangatkan ke disk cache DARI BYTES LOKAL (tanpa unduh
      // ulang server). Dipanggil SEBELUM dispatch supaya poster sudah di disk
      // saat bubble versi-path muncul (kalau dibalik, ada race: bubble render
      // path baru sebelum poster tersimpan → MISS = "card ngeload").
      final posterB64v = posterB64;
      final posterBytes = (posterB64v != null && posterB64v.isNotEmpty)
          ? base64Decode(posterB64v)
          : null;
      unawaited(
        VideoPrefetch.warmOne(path, videoBytes: bytes, posterBytes: posterBytes),
      );
      // PREVIEW PENERIMA (ala WhatsApp): unggah poster (JPEG kecil) ke Storage
      // → penerima tampilkan thumbnail tanpa unduh video penuh. Gagal upload
      // poster TIDAK menggagalkan kirim (video tetap terkirim; penerima lihat
      // placeholder + tap). Karena itu unawaited-ish: kita tunggu hasilnya
      // untuk disertakan di baris pesan, tapi null = lanjut tanpa poster.
      String posterPath = '';
      if (posterBytes != null && posterBytes.isNotEmpty) {
        posterPath = await ProviderScope.containerOf(context, listen: false)
                .read(storageProvider)
                .uploadChatVideoPoster(chatId: photoUploadChatId, bytes: posterBytes) ??
            '';
        dlog('[VideoSend] poster upload path=$posterPath bytes=${posterBytes.length}');
      } else {
        dlog('[VideoSend] poster KOSONG (posterB64=${posterB64v == null ? "null" : posterB64v.length}) → tanpa preview');
      }
      await photoDispatch(
        imageData: path,
        type: videoSendType(isOnce),
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
        // Durasi video (panjang playback) — SELALU dikirim.
        videoDurationMs: durationMs,
        // Path poster untuk preview penerima ('' = tanpa poster).
        videoPoster: posterPath,
      );
      photoFirstBonus(pp);
      photoOnSent(isOnce ? 'video_once' : 'video');
      outboxScrollToBottom();
    } catch (e) {
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        await queueOffline(
          pending: pendingVideo,
          pointsKind: 'image',
          pointsDeducted: true,
          imagePayload: base64Encode(bytes),
          needsUpload: true,
          uploadKind: 'video',
          durationMs: durationMs,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
        );
      } else {
        safeUnawaited(pp.refundChatPoint('image'));
        if (mounted) {
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingVideo.id),
          );
          showChatSnack(context, s.errSendPhoto);
        }
      }
    }
  }

  /// Kirim foto dari base64 yang sudah diproses (dipakai composer preview).
  ///
  /// Bila ada foto tambahan (`albumExtraB64`) → kirim sebagai SATU ALBUM:
  /// semua pesan berbagi `albumId`, caption di foto TERAKHIR, balasan di
  /// foto PERTAMA. HD (bila aktif) diterapkan ke SEMUA foto dari aslinya.
  Future<void> sendPhotoBase64(
    String base64, {
    String text = '',
    MessageModel? reply,
  }) async {
    if (!mounted) return;
    final extras = List<String>.of(albumExtraB64);
    final extrasOrig = List<Uint8List>.of(albumExtraOriginal);
    final isAlbum = extras.isNotEmpty;

    // HD on + original masih ada → proses ulang dari ASLINYA (bukan
    // kompres-ulang hasil preview standar). Berlaku untuk SEMUA foto.
    var payload = base64;
    final original = pendingPhotoOriginal;
    if (photoHd && original != null) {
      payload =
          await NativeImage.processJpeg(original, maxPx: 1920, quality: 90) ??
          base64;
    }
    final payloadExtras = <String>[];
    for (var i = 0; i < extras.length; i++) {
      if (photoHd && i < extrasOrig.length) {
        payloadExtras.add(
          await NativeImage.processJpeg(
                extrasOrig[i],
                maxPx: 1920,
                quality: 90,
              ) ??
              extras[i],
        );
      } else {
        payloadExtras.add(extras[i]);
      }
    }

    if (!isAlbum) {
      await _sendImageLike(
        base64: payload,
        kind: 'image',
        type: 'image',
        text: text,
        reply: reply,
      );
    } else {
      final albumId = _newAlbumId();
      final all = <String>[payload, ...payloadExtras];
      for (var i = 0; i < all.length; i++) {
        await _sendImageLike(
          base64: all[i],
          kind: 'image',
          type: 'image',
          // Caption hanya di foto TERAKHIR (pola WhatsApp).
          text: i == all.length - 1 ? text : '',
          // Balasan hanya di foto PERTAMA.
          reply: i == 0 ? reply : null,
          albumId: albumId,
        );
      }
    }
    albumExtraB64.clear();
    albumExtraOriginal.clear();
    photoClearPreviewState();
  }

  /// UUID v4 sederhana tanpa dependency tambahan (uuid tersedia hanya
  /// sebagai paket transitif — jangan bergantung pada paket tak langsung).
  String _newAlbumId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versi 4
    b[8] = (b[8] & 0x3f) | 0x80; // varian RFC 4122
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final s = [for (var i = 0; i < 16; i++) h(i)].join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<void> _sendImageLike({
    required String base64,
    required String kind,
    required String type,
    String text = '',
    MessageModel? reply,
    String? albumId,
  }) async {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;

    // Timer preview (private): paksa jadi view-once berdurasi.
    final viewSecs = photoViewTimerSecs;
    final effKind = resolvePhotoSendKind(kind, viewSecs);
    final effType = resolvePhotoSendKind(type, viewSecs);
    final pendingPhoto = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: text,
      type: effType,
      imageData: base64,
      timestamp: DateTime.now(),
      durationMs: viewSecs,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      albumId: albumId,
    );
    setState(() => outboxPending.add(pendingPhoto));
    outboxScrollToBottom();

    // Offline: bubble tetap tampil (centang-1) + antre.
    if (!outboxIsOnline) {
      await queueOffline(
        pending: pendingPhoto,
        pointsKind: effKind,
        pointsDeducted: false,
        imagePayload: base64,
        needsUpload: true,
        uploadKind: 'image',
        durationMs: viewSecs,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
      );
      return;
    }

    final pp = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
    final r = await pp.deductBeforeSend(effKind);
    if (r < 0) {
      if (r == -2) {
        await queueOffline(
          pending: pendingPhoto,
          pointsKind: effKind,
          pointsDeducted: false,
          imagePayload: base64,
          needsUpload: true,
          uploadKind: 'image',
          durationMs: viewSecs,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
        );
        photoClearViewTimer();
        return;
      }
      setState(() => outboxPending.removeWhere((m) => m.id == pendingPhoto.id));
      photoClearViewTimer();
      if (!mounted) return;
      final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
      if (r == -1) {
        pp.showOutOfPointsDialog(context, s.isId);
      } else {
        showChatSnack(context, s.errSendPhoto);
      }
      return;
    }

    try {
      final path = await ProviderScope.containerOf(context, listen: false).read(storageProvider).upload(
        chatId: photoUploadChatId,
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (!outboxIsOnline) throw const SocketException('photo upload failed');
        safeUnawaited(pp.refundChatPoint(effKind));
        if (mounted) {
          final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
          showChatSnack(context, s.errSendPhoto);
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingPhoto.id),
          );
        }
        photoClearViewTimer();
        return;
      }
      // Isi path == base64 yang baru di-upload → daftarkan decode-nya supaya
      // bubble versi server langsung tampil (tidak download + kotak dulu).
      warmPhotoCacheForPath(path, base64);
      final msgId = await photoDispatch(
        imageData: path,
        type: effType,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
        viewOnceSecs: viewSecs,
        albumId: albumId,
      );
      // Simpan thumb ke DISK (PhotoCache) dari base64 asli → cold start
      // berikutnya HIT disk (anti-blink foto kiriman sendiri; dulu hanya
      // warm memori `warmPhotoCacheForPath` sehingga restart = blink).
      if (msgId != null && msgId.isNotEmpty) {
        unawaited(PhotoCache.instance
            .save(photoCacheChatKey, msgId, base64));
        // View-once: pindahkan state dari id PENDING ke id SERVER supaya
        // foto yang sudah ter-decode di bubble optimistik langsung dipakai
        // (tanpa spinner/blink saat bubble berganti ke pesan server).
        if (effType == 'view_once' || effType == 'video_once') {
          migrateViewOnceState(pendingPhoto.id, msgId);
        }
      }
      if (kind == 'image') photoFirstBonus(pp);
      photoOnSent(kind);
      photoClearViewTimer();
      outboxScrollToBottom();
    } catch (e) {
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        // Poin sudah dipotong, jangan refund — dipakai saat flush.
        await queueOffline(
          pending: pendingPhoto,
          pointsKind: effKind,
          pointsDeducted: true,
          imagePayload: base64,
          needsUpload: true,
          uploadKind: 'image',
          durationMs: viewSecs,
          repliedToId: reply?.id,
          repliedToText: reply?.text,
          repliedToSenderName: reply?.senderName,
        );
      } else {
        safeUnawaited(pp.refundChatPoint(effKind));
        if (mounted) {
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingPhoto.id),
          );
          final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
          showChatSnack(context, s.errSendPhoto);
        }
      }
      photoClearViewTimer();
    }
  }
}
