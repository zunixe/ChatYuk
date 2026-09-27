import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/storage_provider.dart';
import '../utils.dart';
import '../core/media/chat_photo_helper.dart';
import '../core/photo_quality_pref.dart';
import '../core/cache/offline_outbox.dart';
import '../services/storage_photo_service.dart';
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
  Future<void> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
    String text = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    int? viewOnceSecs,
    /// Durasi VIDEO (ms) untuk bubble + validasi server. Null = bukan video.
    int? videoDurationMs,
  });

  /// Timer view-once yang dipilih di preview (detik; null = foto normal).
  /// Hanya private screen yang mengisi — room default null (tak berubah).
  int? get photoViewTimerSecs => null;

  /// Reset pilihan timer setelah preview terkirim/dibatalkan.
  void photoClearViewTimer() {}

  /// Folder upload storage (private: chatId; room: `room_<id>`).
  String get photoUploadChatId;

  /// Seed watermark view-once (private: uid lawan; room: id room).
  String get photoSeed;

  /// Efek setelah foto sukses terkirim (private: bonus + fallback; room: no-op).
  void photoOnSent(String kind);

  /// Bonus sekali pakai khusus private (`first_photo`); room = no-op.
  void photoFirstBonus(PointsProvider pp);

  /// Set preview foto di composer (private: + fokus & scroll; room: set saja).
  void photoSetPreview(String base64);

  /// Set preview VIDEO di composer (poster + durasi). Hanya private yang
  /// mengisi; room default no-op (video room belum aktif).
  void videoSetPreview({
    required String path,
    required String posterBase64,
    required int durationMs,
  }) {}

  /// Buang preview video (batal/kirim). Room default no-op.
  void videoClearPreview() {}

  /// Path video yang sedang di-preview (null = tidak ada). Room selalu null.
  String? get pendingVideoPath => null;

  /// True bila fitur video aktif di layar ini (private). Room: false.
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

  /// Tombol galeri: ambil → taruh di preview (caption + toggle HD),
  /// ala WhatsApp. Kirim terjadi dari tombol send composer.
  Future<void> photoPickFromGalleryToPreview() async {
    final picked = await _photoPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final processed = await photoProcess(bytes);
    await _openPreview(bytes, processed);
  }

  /// Validasi ukuran + resize isolate. Return base64, null bila gagal
  /// (pesan error sudah tampil).
  Future<String?> photoProcess(Uint8List bytes) async {
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgFileTooLarge)));
      }
      return null;
    }
    final base64 = await compute(processChatImage, bytes);
    if (base64 == null && mounted) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
    }
    return base64;
  }

  /// Ambil bytes gambar untuk view-once (default: galeri). Di-override di
  /// test supaya alur caption bisa diuji tanpa plugin image_picker.
  Future<Uint8List?> pickViewOnceImage() async {
    final picked = await _photoPicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  /// Proses bytes → base64 (watermark view-once bila aktif). Di-override di
  /// test supaya alur caption diuji tanpa `compute()` (isolate di test-fake
  /// bisa menggantung).
  Future<String?> processViewOnceBytes(Uint8List bytes) async {
    final auth = context.read<AuthProvider>();
    return auth.watermarkEnabled
        ? compute(processViewOnceImage, (bytes, photoSeed))
        : compute(processChatPhoto, bytes);
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
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    return _processPickedVideo(path, toast: toast);
  }

  /// Kompres + poster + preview dari path video (dipakai galeri & rekam).
  /// Validasi durasi (>60 dtk ditolak) dan ukuran hasil.
  Future<bool> _processPickedVideo(
    String path, {
    required void Function(String) toast,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final storage = context.read<StorageProvider>();
    // 1) Cek durasi ASLI sebelum kompres (tolak >60 dtk lebih awal —
    //    jangan buang waktu kompres video 5 menit).
    final rawMs = await storage.videoDurationMs(path);
    if (!mounted) return false;
    if (rawMs > 0 && rawMs > StoragePhotoService.chatVideoMaxMs) {
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
    if (bytes.length > StoragePhotoService.chatVideoMaxBytes) {
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
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final durationMs = pendingVideoMs;
    // Tangkap "sekali lihat" SEBELUM clear preview: videoClearPreview()
    // me-reset _pendingVideoOnce=false → kalau dibaca setelah clear, video
    // sekali-lihat selalu terkirim sebagai video biasa (bug: type='video').
    final isOnce = videoOnceSelected;
    videoClearPreview();

    final file = File(path);
    final bytes = await file.exists() ? await file.readAsBytes() : null;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.videoCompressFail)));
      }
      return;
    }
    await _sendVideoLike(
      bytes: bytes,
      durationMs: durationMs,
      text: text,
      reply: reply,
      isOnce: isOnce,
    );
  }

  /// Durasi video preview (ms). WAJIB getter (bukan field) supaya layar
  /// bisa meng-override dengan state-nya — field di mixin akan MENUTUPI
  /// getter layar dan selalu bernilai 0 (durasi hilang saat kirim).
  int get pendingVideoMs => 0;

  /// Jalur kirim video: optimistic bubble → poin → upload → dispatch.
  /// Tanpa view-once (video tidak punya mode sekali lihat).
  Future<void> _sendVideoLike({
    required Uint8List bytes,
    required int durationMs,
    String text = '',
    MessageModel? reply,
    bool isOnce = false,
  }) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final s = context.read<LocaleProvider>().s;

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
      );
      return;
    }

    final pp = context.read<PointsProvider>();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
      return;
    }

    try {
      final path = await StoragePhotoService.instance.uploadChatVideo(
        chatId: photoUploadChatId,
        bytes: bytes,
      );
      if (path == null || path.isEmpty) {
        if (!outboxIsOnline) {
          throw const SocketException('video upload failed');
        }
        safeUnawaited(pp.refundChatPoint('image'));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingVideo.id),
          );
        }
        return;
      }
      // "Sekali lihat" video ditandai lewat TYPE (video_once) — bukan
      // durationMs yang sudah dipakai untuk panjang video. Nilai `isOnce`
      // ditangkap pemanggil SEBELUM preview dibersihkan.
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
        }
      }
    }
  }

  /// Kirim foto dari base64 yang sudah diproses (dipakai composer preview).
  Future<void> sendPhotoBase64(
    String base64, {
    String text = '',
    MessageModel? reply,
  }) async {
    if (!mounted) return;
    // HD on + original masih ada → proses ulang dari ASLINYA (bukan
    // kompres-ulang hasil preview standar).
    var payload = base64;
    final original = pendingPhotoOriginal;
    if (photoHd && original != null) {
      payload = await compute(processChatImageHd, original) ?? base64;
    }
    await _sendImageLike(
      base64: payload,
      kind: 'image',
      type: 'image',
      text: text,
      reply: reply,
    );
    photoClearPreviewState();
  }

  Future<void> _sendImageLike({
    required String base64,
    required String kind,
    required String type,
    String text = '',
    MessageModel? reply,
  }) async {
    final auth = context.read<AuthProvider>();
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

    final pp = context.read<PointsProvider>();
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
      final s = context.read<LocaleProvider>().s;
      if (r == -1) {
        pp.showOutOfPointsDialog(context, s.isId);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
      return;
    }

    try {
      final path = await StoragePhotoService.instance.upload(
        chatId: photoUploadChatId,
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (!outboxIsOnline) throw const SocketException('photo upload failed');
        safeUnawaited(pp.refundChatPoint(effKind));
        if (mounted) {
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
          setState(
            () => outboxPending.removeWhere((m) => m.id == pendingPhoto.id),
          );
        }
        photoClearViewTimer();
        return;
      }
      await photoDispatch(
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
      );
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
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
        }
      }
      photoClearViewTimer();
    }
  }
}
