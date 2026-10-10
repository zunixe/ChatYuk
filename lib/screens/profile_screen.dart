import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rv;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/media/native_image.dart';
import 'package:image_cropper/image_cropper.dart';
import '../widgets/async_photo.dart';
import '../widgets/verified_badge.dart';
import '../providers/riverpod/phone_verify_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import 'profile/widgets/profile_widgets.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/device_info_provider.dart';
import '../providers/riverpod/online_users_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../utils.dart';
import 'link_email_screen.dart';
import 'settings_screen.dart';
import 'contact_screen.dart';
import 'donate_screen.dart';
import '../core/admin_gate.dart';
import 'leaderboard_screen.dart';
import 'point_history_screen.dart';
import 'social_list_screen.dart';
import 'friend_requests_screen.dart';
import 'subscriptions_screen.dart';
import '../core/perf/perf_probe.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/riverpod/locale_provider.dart';

part 'profile/profile_core.dart';
part 'profile/profile_photos.dart';
part 'profile/profile_build.dart';
part 'profile/profile_body.dart';

// Avatar profil (resize 640×640 + JPEG q85) kini di NATIVE via
// `NativeImage.processSquare` (fallback Dart di chat_photo_helper.dart).
// `processAvatar` dipertahankan sebagai kontrak test (delegasi ke native).
@visibleForTesting
Future<String?> processAvatar(Uint8List bytes) =>
    NativeImage.processSquare(bytes, size: 640, quality: 85);

// Galeri foto + preview blur kini diproses di NATIVE via
// `NativeImage.processGalleryPhoto` (fallback ke `dartProcessGalleryPhoto`
// Dart di lib/core/media/chat_photo_helper.dart).

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// State + field bersama ProfileScreen — dipakai mixin (file `part`).
abstract class _ProfileBase extends ConsumerState<ProfileScreen> {
  bool _uploading = false;

  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;

  final TextEditingController _hashtagCtrl = TextEditingController();
  List<String> _hashtags = [];
  // About diedit inline di tempat (tanpa bottom sheet).
  bool _editingAbout = false;
  bool _savingAbout = false;
  final TextEditingController _aboutCtrl = TextEditingController();
  bool _savingHashtags = false;
  Uint8List? _cachedAvatarBytes;
  String? _lastAvatarB64;
  // UID user yang datanya sedang ditampilkan — dipakai mendeteksi swap
  // sesi dummy ⇄ admin (ProfileScreen hidup di IndexedStack, initState
  // tidak jalan lagi saat swap), supaya foto/hashtag/avatar ikut ganti.
  String? _loadedUid;
  // Future label versi dibuat SEKALI (bukan di build) — dulu `FutureBuilder(future:
  // ProviderScope.containerOf(context, listen: false).read(deviceInfoProvider).appVersionLabel())` membuat Future BARU
  // tiap build → FutureBuilder re-subscribe → "setState() called during build".
  Future<String>? _appVersionFuture;

  // Kontrak lintas-mixin.
  Widget _buildBodySliver(
    BuildContext context,
    S s,
    UserModel? profile,
    String? uid,
    bool isAnon,
    bool dummyActive,
    bool dummySessionActive,
    bool emailConfirmed,
    String? userEmail,
    bool pointsEnabled,
    int pointsValue,
    int extraPhotoSlots,
    bool yukcoinV2Active,
  );
  // ignore: unused_element
  Color _statusColor(String status);
  // ignore: unused_element
  String _statusLabel(String status, S s);
  Future<void> _editProfile();
  Future<void> _saveAbout();
  // ignore: unused_element
  Future<void> _editSubscriptionPrice(BuildContext context);
  Future<void> _loadPhotos();
  void _pickGalleryFromSource();
  Future<void> _buyExtraSlots();
  Future<void> _confirmDeletePhoto(UserPhoto photo);
  Future<void> _showAvatarOptions();
  void _showAvatarZoom(Uint8List? bytes, Color bgColor, String initial);
  void _addHashtag(String raw);
  void _removeHashtag(String tag);
  void _startEditAbout(String current);
  void _cancelEditAbout();
}

class _ProfileScreenState extends _ProfileBase
    with _ProfileCoreMx, _ProfilePhotosMx, _ProfileBuildMx, _ProfileBodyMx {}
