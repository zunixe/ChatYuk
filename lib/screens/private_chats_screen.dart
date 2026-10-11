import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../config/strings.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/avatar_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/online_users_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../utils.dart';
import '../widgets/person_avatar.dart';
import '../widgets/verified_badge.dart';
import '../widgets/social_counts_line.dart';
import '../widgets/chat_route.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/app_gesture.dart';
import '../core/perf/perf_probe.dart';
import '../core/nav_guard.dart';
import '../core/chat/chat_filter.dart';
import '../core/chat/chat_location.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/video_prefetch.dart';
import '../widgets/message/photo_prefetch.dart';
import '../config/theme.dart';
import 'private_chats/private_chats_widgets.dart';

part 'private_chats/private_chats_select.dart';
part 'private_chats/private_chats_filter.dart';
part 'private_chats/private_chats_build.dart';

const int _pageSize = 20;

class PrivateChatsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final String? externalQuery;
  const PrivateChatsScreen({
    super.key,
    this.embedded = false,
    this.externalQuery,
  });

  @override
  ConsumerState<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

/// State + field bersama PrivateChatsScreen — dipakai mixin (file `part`).
abstract class _PcBase extends ConsumerState<PrivateChatsScreen> {
  Stream<List<PrivateChatInfo>>? _stream;
  List<PrivateChatInfo>? _initial;
  String? _boundUid;
  int _page = 1;
  final ScrollController _scrollCtrl = ScrollController();
  int _lastTotal = 0;
  // Notifier paginasi — scroll menambah halaman tanpa rebuild sehalaman.
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(1);
  // List terlihat + jumlah arsip disiarkan lewat notifier: hanya bagian
  // list yang rebuild, bukan seluruh halaman (AppBar/bar seleksi).
  final ValueNotifier<List<PrivateChatInfo>> _listNotifier =
      ValueNotifier<List<PrivateChatInfo>>(const []);
  final ValueNotifier<int> _archivedNotifier = ValueNotifier<int>(0);
  // Input terakhir yang dipakai menghitung _lastFiltered.
  bool _recomputeDirty = true;
  String _lastQueryUsed = '';
  Map<String, String> _statusMap = const {};
  Map<String, String> _nameMap = const {};
  Set<String> _friendSet = const {};
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;
  // Tampilan arsip (gaya WhatsApp): list hanya chat terarsip.
  bool _showArchived = false;
  int _archivedCount = 0;

  /// Filter daftar chat (semua/belum dibaca/teman/anon/terdaftar).
  ChatFilter _chatFilter = ChatFilter.all;

  /// Jumlah per filter — disiarkan lewat notifier supaya mengubah filter
  /// hanya me-rebuild baris chip, bukan seluruh halaman.
  final ValueNotifier<
    ({int all, int unread, int friends, int anon, int registered})
  >
  _countsNotifier =
      ValueNotifier<
        ({int all, int unread, int friends, int anon, int registered})
      >((all: 0, unread: 0, friends: 0, anon: 0, registered: 0));
  List<PrivateChatInfo> _lastFiltered = [];
  List<PrivateChatInfo> _lastChats = [];

  // Kontrak lintas-mixin.
  void _clearSelection();
  void _toggleSelect(String chatId);
  Future<void> _openChat(PrivateChatInfo chat);
  Future<void> _deleteChat(String uid, String chatId);
  Future<void> _deleteSelected(String uid);
  bool _sameStatusMap(Map<String, String> a, Map<String, String> b);
  List<Widget> _selectionActions(String uid, S s);
  Widget _selectionBar(String uid, S s, {bool overlay});
  Widget _chatFilterBar(S s);
  Widget _archivedToggle(S s, int archivedCount);
  void _recomputeFiltered({
    required String myUid,
    required String query,
    Map<String, String>? liveNameMap,
    // ignore: unused_element_parameter
    Map<String, String>? pendingStatus,
    // ignore: unused_element_parameter
    bool notify = true,
  });
}

class _PrivateChatsScreenState extends _PcBase
    with _PcSelectMx, _PcFilterMx, _PcBuildMx {}
