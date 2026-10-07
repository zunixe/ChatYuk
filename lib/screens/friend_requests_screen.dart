import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../widgets/person_avatar.dart';
import '../providers/riverpod/theme_provider.dart';
import '../config/theme.dart';

class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen> {
  SocialNotifier get _service => ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier);
  bool _loading = true;
  List<Map<String, dynamic>> _inbox = [];
  List<Map<String, dynamic>> _outbox = [];
  // Jumlah terakhir yang terlihat layar ini — berubah (request masuk /
  // direspons dari device lain) → muat ulang otomatis.
  int? _knownCount;

  @override
  void initState() {
    super.initState();
    _knownCount = ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier).friendRequestCount;
    _load();
  }

  Future<void> _load() async {
    final inbox = await _service.friendRequestInbox();
    final outbox = await _service.friendRequestOutbox();
    if (!mounted) return;
    setState(() {
      _inbox = inbox;
      _outbox = outbox;
      _loading = false;
    });
  }

  Future<void> _respond(Map<String, dynamic> req, bool accept) async {
    final id = (req['id'] as num?)?.toInt() ?? 0;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.respondFriendRequest(id, accept);
      if (accept && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.friendRequestAccepted)),
        );
      }
      await _load();
      if (mounted) ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier).refreshInbox();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  /// Batalkan friend request milik sendiri (baris di Outbox).
  Future<void> _cancel(Map<String, dynamic> req) async {
    final id = (req['id'] as num?)?.toInt() ?? 0;
    final targetUid = '${req['uid'] ?? ''}';
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await _service.cancelFriendRequest(id, targetUid: targetUid);
      if (ok) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.friendRequestCancelled)),
        );
        await _load();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // Request masuk selagi layar terbuka → muat ulang (realtime provider
    // sudah update count; daftar lokal ikut segar tanpa pull-to-refresh).
    final count = ref.watch(
      socialProvider.select((sp) => sp.friendRequestCount),
    );
    if (!_loading && _knownCount != count) {
      _knownCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.friendRequestTitle)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _inbox.isEmpty && _outbox.isEmpty
          ? Center(
              child: Text(
                s.friendRequestEmpty,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: Builder(
                builder: (ctx) {
                  // Susun daftar datar: label section + baris, sekali saja,
                  // lalu render lazy via builder (dulu ListView eager
                  // membangun SEMUA tile sekaligus → lag saat setState).
                  final rows = <Widget>[];
                  if (_inbox.isNotEmpty) {
                    rows.add(
                      Text(
                        s.friendRequestInbox,
                        style: AppText.label.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                    rows.add(const SizedBox(height: 6));
                    for (final r in _inbox) {
                      rows.add(
                        _RequestTile(
                          entry: r,
                          pending: true,
                          onAccept: () => _respond(r, true),
                          onReject: () => _respond(r, false),
                        ),
                      );
                    }
                    rows.add(const SizedBox(height: 16));
                  }
                  if (_outbox.isNotEmpty) {
                    rows.add(
                      Text(
                        s.btnFriendRequested,
                        style: AppText.label.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                    rows.add(const SizedBox(height: 6));
                    for (final r in _outbox) {
                      rows.add(
                        _RequestTile(
                          entry: r,
                          pending: false,
                          onCancel: () => _cancel(r),
                        ),
                      );
                    }
                  }
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      MediaQuery.of(ctx).padding.bottom + 24,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => rows[i],
                  );
                },
              ),
            ),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  final Map<String, dynamic> entry;
  final bool pending;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  const _RequestTile({
    required this.entry,
    required this.pending,
    this.onAccept,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final name = '${entry['nickname'] ?? 'Anon'}';
    final uid = '${entry['uid'] ?? ''}';
    final registered = entry['is_registered'] == true;
    final gender = '${entry['gender'] ?? ''}';
    final avatar = '${entry['avatar'] ?? ''}';
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Warna/ring gender — konsisten dgn menu Online & chat.
          PersonAvatar(
            uid: uid,
            name: name,
            gender: gender,
            avatarB64: avatar,
            size: 40,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: AppText.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (registered) ...[
                  SizedBox(width: 4),
                  Icon(Icons.verified, size: 14, color: Color(0xFF4A90E2)),
                ],
              ],
            ),
          ),
          if (pending) ...[
            TextButton(
              onPressed: onReject,
              child: Text(
                s.btnCancel,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: onAccept,
              child: Text(s.btnConfirm, style: TextStyle(color: Colors.white)),
            ),
          ] else ...[
            // Outbox memuat SEMUA riwayat (pending/accepted/rejected) —
            // tombol Batal HANYA untuk yang masih pending. Backend
            // `cancel_friend_request` menolak non-pending (not_pending),
            // jadi menampilkannya = tombol yang pasti gagal.
            Builder(
              builder: (_) {
                final st = '${entry['status'] ?? 'pending'}';
                if (st == 'pending') {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.btnFriendRequested,
                        style: AppText.caption
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: onCancel,
                        child: Text(
                          s.btnCancel,
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    ],
                  );
                }
                return Text(
                  st == 'accepted'
                      ? s.friendRequestStatusAccepted
                      : s.friendRequestStatusRejected,
                  style: AppText.caption.copyWith(
                    color: st == 'accepted'
                        ? AppTheme.online
                        : AppTheme.textSecondary,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
