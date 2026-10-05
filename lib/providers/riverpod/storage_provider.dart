import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show ResizeMode;
import '../../services/storage_photo_service.dart';
export '../../services/storage_photo_service.dart' show StoragePhotoService;

/// Storage (Riverpod) — wrapper action-only untuk [StoragePhotoService].
/// `services/` langsung (aturan boundary AGENTS.md).
///
/// Bukan state bisnis; hanya jembatan. Widget boleh tetap pakai service
/// langsung (aturan hanya untuk screen).
class StorageNotifier {
  final StoragePhotoService service;
  StorageNotifier([StoragePhotoService? service])
      : service = service ?? StoragePhotoService.instance;

  Future<String?> upload({required String chatId, required String base64}) =>
      service.upload(chatId: chatId, base64: base64);

  Future<String?> uploadVoice({
    required String chatId,
    required Uint8List bytes,
  }) =>
      service.uploadVoice(chatId: chatId, bytes: bytes);

  Future<String?> uploadPostImage({
    required String uid,
    required String base64,
  }) =>
      service.uploadPostImage(uid: uid, base64: base64);

  Future<String?> uploadStoryImage({
    required String uid,
    required String base64,
  }) =>
      service.uploadStoryImage(uid: uid, base64: base64);

  Future<String?> uploadStoryVideo({
    required String uid,
    required Uint8List bytes,
  }) =>
      service.uploadStoryVideo(uid: uid, bytes: bytes);

  String storyVideoPath(String uid) => service.storyVideoPath(uid);
  bool isStoryVideoPath(String v) => service.isStoryVideoPath(v);

  Future<File?> compressStoryVideo(
    String srcPath, {
    void Function(double progress01)? onProgress,
    int? startMs,
    int? durationMs,
  }) =>
      service.compressStoryVideo(
        srcPath,
        onProgress: onProgress,
        startMs: startMs,
        durationMs: durationMs,
      );

  Future<Uint8List?> storyVideoPoster(String videoPath) =>
      service.storyVideoPoster(videoPath);

  // ── VIDEO CHAT ──
  Future<String?> uploadChatVideo({
    required String chatId,
    required Uint8List bytes,
  }) =>
      service.uploadChatVideo(chatId: chatId, bytes: bytes);

  String chatVideoPath(String chatId) => service.chatVideoPath(chatId);
  bool isChatVideoPath(String v) => service.isChatVideoPath(v);

  Future<File?> compressChatVideo(
    String srcPath, {
    void Function(double progress01)? onProgress,
  }) =>
      service.compressChatVideo(srcPath, onProgress: onProgress);

  Future<int> videoDurationMs(String srcPath) =>
      service.videoDurationMs(srcPath);

  Future<String?> uploadRoomIcon({
    required String uid,
    required String base64,
  }) =>
      service.uploadRoomIcon(uid: uid, base64: base64);

  Future<String?> download(String path) => service.download(path);

  Future<Uint8List?> downloadBytes(String path) => service.downloadBytes(path);

  Future<Uint8List?> downloadThumbBytes(
    String path, {
    int width = 160,
    int? height,
    ResizeMode? resize,
    int quality = 70,
  }) =>
      service.downloadThumbBytes(
        path,
        width: width,
        height: height,
        resize: resize,
        quality: quality,
      );

  bool isPath(String value) => service.isPath(value);
  bool isRoomIconPath(String value) => service.isRoomIconPath(value);
  bool isAvatarPath(String value) => service.isAvatarPath(value);
  bool isGalleryPath(String value) => service.isGalleryPath(value);
  bool isStoryPath(String value) => service.isStoryPath(value);
  bool isVoicePath(String value) => service.isVoicePath(value);
  String avatarPath(String uid) => service.avatarPath(uid);
  String photoPath(String uid) => service.photoPath(uid);
  String storyPath(String uid) => service.storyPath(uid);
  String voicePath(String chatId) => service.voicePath(chatId);
  String newPath(String chatId) => service.newPath(chatId);
}

final storageProvider = Provider<StorageNotifier>((_) => StorageNotifier());
