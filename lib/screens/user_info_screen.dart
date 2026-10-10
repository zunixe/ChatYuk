import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../config/strings.dart';
import '../core/nav_guard.dart';
import '../utils.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/call_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../providers/riverpod/auth_provider.dart';
import '../services/storage_photo_service.dart';
import '../services/avatar_service.dart';
import 'user_info/user_info_widgets.dart';
import '../widgets/verified_badge.dart';
import '../widgets/social_actions.dart';
import '../widgets/call_permission_dialog.dart';
import '../core/call/call_permissions.dart';
import '../providers/riverpod/theme_provider.dart';
import 'call_screen.dart';
import 'private_chat_screen.dart';
import 'social_list_screen.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/privacy_provider.dart';
import '../config/theme.dart';

part 'user_info/user_info_init.dart';
part 'user_info/user_info_actions.dart';
part 'user_info/user_info_build.dart';

const Duration _loadTimeout = Duration(seconds: 10);

class UserInfoScreen extends ConsumerStatefulWidget {
  final String userId;
  final String fallbackName;
  // Seed profil awal (mis. dari baris Top Aktif yang sudah punya nickname /
  // gender / avatar) — frame pertama langsung render ISI, bukan placeholder
  // loading. Refresh server tetap jalan di belakang dan menimpa diam-diam.
  final UserModel? initialProfile;
  const UserInfoScreen({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.initialProfile,
  });

  @override
  ConsumerState<UserInfoScreen> createState() => _UserInfoScreenState();
}

/// State + field bersama UserInfoScreen — dipakai mixin (file `part`).
abstract class _UserInfoBase extends ConsumerState<UserInfoScreen> {
  UserModel? _profile;
  bool _loading = true;
  // Gagal total (timeout/network) saat profil masih null — tampilkan
  // error + tombol retry, jangan spinner selamanya.
  bool _loadError = false;
  // Avatar (base64) dimuat TERPISAH dari profil: profil teks muncul duluan,
  // foto menyusul. Dulu avatar diunduh di dalam getProfileById → kalau
  // lambat, SELURUH profil kena timeout 10 dtk → layar "Coba lagi"
  // (keluhan "profilnya ga muncul" padahal datanya ada).
  String _avatarB64 = '';
  // Bytes avatar ter-decode — di-cache supaya TIDAK decode base64 di dalam
  // build() tiap rebuild (dulu `base64Decode(_avatarB64)` di _profileCarousel
  // → decode ulang tiap setState/animation). Decode hanya saat string berubah.
  String _avatarB64Cached = '';
  Uint8List? _avatarBytesCached;
  // Path avatar terakhir + penanda sudah pernah dicoba, supaya kegagalan
  // sesaat bisa dicoba ulang sekali (foto tidak "menghilang" permanen
  // selama layar terbuka).
  String _avatarPath = '';
  bool _avatarRetried = false;
  List<UserPhoto> _photos = [];
  // Bytes galeri per photo-id — decode SEKALI, bukan tiap build.
  // `galleryPage()` dulu `base64Decode` di dalam build → tiap rebuild
  // (update status/sosial, animasi pop/back) decode ulang semua foto → jank,
  // paling terasa saat back dari profil ke sheet Top Aktif.
  final Map<String, Uint8List> _galleryBytes = {};
  String _status = 'offline';
  StreamSubscription<String>? _statusSub;

  // Status sosial terhadap user ini.
  bool _following = false;
  bool _friend = false;
  bool _friendRequestSent = false;
  bool _subscribed = false;
  bool _busySocial = false;

  // Carousel foto: geser kiri-kanan (avatar + foto terbuka).
  late final PageController _carouselCtrl = PageController();
  int _carouselIndex = 0;

  // Kontrak lintas-mixin.
  Future<void> _addFriend();
  Future<void> _unfriend();
  Future<void> _cancelFriendRequest();
  Future<void> _toggleFollow();
  Future<void> _subscribe();
  Future<void> _startChat();
  Future<void> _startCall(BuildContext ctx, String callType);
  void _subscribeStatus(UserModel? fresh);
  void _showFollowVsFriendInfo(BuildContext context, S s);
  void _showPhotoViewer(List<UserPhoto> photos, int index);
  Future<void> _load();
  Future<void> _loadAvatar(String path);
  Future<void> _loadPhotos();
  Future<void> _loadSocial();
  void _retryLoad();
  Uint8List? _decodedAvatarBytes();
  Uint8List? _galleryBytesOf(UserPhoto photo);
}

class _UserInfoScreenState extends _UserInfoBase
    with _UiInitMx, _UiActionsMx, _UiBuildMx {}
