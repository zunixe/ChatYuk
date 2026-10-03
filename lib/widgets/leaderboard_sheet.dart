import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../models/user_model.dart';
import '../providers/points_provider.dart';
import '../providers/avatar_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/social_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/storage_provider.dart';
import '../services/avatar_service.dart';
import '../core/cache/media_disk_cache.dart';
import '../screens/user_info_screen.dart';
import 'profile_avatar.dart';
import 'gender_avatar.dart';

/// "Top Aktif" versi COMPACT untuk ditampilkan sebagai bottom sheet —
/// langsung di halaman Pengguna Online (bukan halaman baru). Ringkas:
/// tab Mingguan/Sepanjang Masa, highlight top-3, daftar padat, bar
/// peringkat-diri di bawah. Tap nama → profil user; ada tombol
/// Ikuti/Tambah Teman cepat di tiap baris.
class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key});

  /// Cache hasil Top Aktif per-scope (weekly/alltime) — supaya buka ulang
  /// INSTAN (tidak "selalu loading"). Diisi setelah RPC sukses; refresh
  /// background tetap jalan saat dibuka (data mungkin berubah).
  static final Map<String, ({List<dynamic> entries, Map<String, dynamic>? me})>
      _cache = {};
  static final Map<String, DateTime> _cacheAt = {};
  static const _cacheFreshTtl = Duration(seconds: 60);

  /// Kontrak cache Top Aktif — dibuka test (bukan API produksi).
  @visibleForTesting
  static bool hasCacheFor(String scope) => _cache.containsKey(scope);

  @visibleForTesting
  static void seedCacheForTest(
    String scope, {
    required List<dynamic> entries,
    Map<String, dynamic>? me,
    DateTime? at,
  }) {
    _cache[scope] = (entries: entries, me: me);
    _cacheAt[scope] = at ?? DateTime.now();
  }

  @visibleForTesting
  static void clearCacheForTest() {
    _cache.clear();
    _cacheAt.clear();
  }

  @visibleForTesting
  static Duration get cacheFreshTtl => _cacheFreshTtl;

  /// Tampilkan sebagai bottom sheet melengkung dari halaman pemanggil.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LeaderboardSheet(),
    );
  }

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet> {
  PointsProvider get _service => context.read<PointsProvider>();
  String _scope = 'weekly';
  bool _loading = true;
  List<dynamic> _entries = [];
  Map<String, dynamic>? _me;
  // Cache hasil per-scope milik sheet ini (weekly/alltime) — tampil instan
  // saat ganti tab. Di-seed dari LeaderboardSheet._cache di initState.
  final Map<String, ({List<dynamic> entries, Map<String, dynamic>? me})>
      _scopeCache = {};
  // Timer penunda: menahan `_load` sampai animasi buka sheet selesai supaya
  // kerja berat (render 50 baris + avatar) tidak jatuh bersamaan transisi →
  // tidak jank "pas mau kebuka". (dulu _load dipanggil langsung di initState)
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    // Isi dari cache DULU (instan, tanpa loading) — kalau ada.
    final cached = LeaderboardSheet._cache[_scope];
    if (cached != null) {
      _entries = cached.entries;
      _me = cached.me;
      _loading = false;
    }
    // Terapkan cache scope lain juga (saat ganti tab) tersedia instan.
    for (final e in LeaderboardSheet._cache.entries) {
      _scopeCache[e.key] = e.value;
    }
    // Muat/refresh dengan buffer supaya tidak jatuh di tengah animasi buka.
    // Lebih pendek kalau sudah ada cache (data sudah tampil, refresh diam).
    final delay = cached != null ? 120 : 300;
    _settleTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Ada cache → JANGAN tampilkan spinner (data sudah tampil). Refresh diam.
    final hasCache = _scopeCache.containsKey(_scope);
    if (!hasCache) setState(() => _loading = true);
    // Cache masih fresh (<TTL) → skip RPC sama sekali (data kemungkinan sama).
    final at = LeaderboardSheet._cacheAt[_scope];
    if (hasCache &&
        at != null &&
        DateTime.now().difference(at) < LeaderboardSheet._cacheFreshTtl) {
      return;
    }
    try {
      final res = await _service.activityLeaderboard(_scope);
      if (!mounted) return;
      final entries = (res['entries'] as List?) ?? [];
      final me = res['me'] is Map ? Map<String, dynamic>.from(res['me']) : null;
      // Simpan ke cache (static + lokal per-scope).
      LeaderboardSheet._cache[_scope] = (entries: entries, me: me);
      LeaderboardSheet._cacheAt[_scope] = DateTime.now();
      _scopeCache[_scope] = (entries: entries, me: me);
      setState(() {
        _entries = entries;
        _me = me;
        _loading = false;
      });
      unawaited(
        context.read<AvatarProvider>().prefetch(
          _entries
              .map((e) => '${(e as Map)['uid'] ?? ''}')
              .where((u) => u.isNotEmpty)
              .toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Gagal refresh TAPI ada cache → pertahankan data lama (jangan kosongkan).
      if (hasCache) return;
      setState(() {
        _entries = [];
        _me = null;
        _loading = false;
      });
    }
  }

  void _switchScope(String scope) {
    if (scope == _scope) return;
    // Ganti tab: pakai cache scope itu kalau ada (instan, tanpa loading),
    // lalu refresh diam. Kalau belum ada → tampilkan loading saat fetch.
    final cached = _scopeCache[scope];
    setState(() {
      _scope = scope;
      if (cached != null) {
        _entries = cached.entries;
        _me = cached.me;
        _loading = false;
      } else {
        _entries = [];
        _me = null;
        _loading = true;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grip
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header: judul + tab segmented compact
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.topActiveTitle,
                    style: AppText.titleEmphasis,
                  ),
                ),                _SegmentedScope(
                  scope: _scope,
                  onChanged: _switchScope,
                  weeklyLabel: s.topActiveTabWeekly,
                  allTimeLabel: s.topActiveTabAllTime,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _scope == 'weekly'
                        ? s.topActiveHintWeekly
                        : s.topActiveHintAllTime,
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Isi
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                : _entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          s.topActiveEmpty,
                          style: AppText.body.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.only(
                          top: 6,
                          // viewPadding (bukan padding): inset nav bar murni
                          // yang TAK dikonsumsi bottom-sheet. `padding` kadang
                          // 0 di konteks sheet → konten nembus menu Android.
                          bottom:
                              12 + MediaQuery.viewPaddingOf(context).bottom + (_me == null ? 0 : 8),
                        ),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 60,
                          color: AppTheme.divider.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (_, i) => RepaintBoundary(
                          // Batasi repaint ke baris ini saja: scroll/animasi
                          // sheet tak memaksa seluruh 50 baris digambar ulang.
                          child: LeaderboardRow(
                            entry: Map<String, dynamic>.from(_entries[i] as Map),
                            s: s,
                            scope: _scope,
                          ),
                        ),
                      ),
          ),
          // Bar peringkat sendiri
          if (_me != null && !_loading)
            _MyRankBar(
              rank: (_me!['rank'] as num?)?.toInt(),
              bottomInset: media.viewPadding.bottom,
            ),
        ],
      ),
    );
  }
}

/// Toggle Mingguan / Sepanjang Masa bergaya segmented pill (compact).
class _SegmentedScope extends StatelessWidget {
  final String scope;
  final ValueChanged<String> onChanged;
  final String weeklyLabel;
  final String allTimeLabel;
  const _SegmentedScope({
    required this.scope,
    required this.onChanged,
    required this.weeklyLabel,
    required this.allTimeLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String value, String label) {
      final active = scope == value;
      return GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: active ? Colors.white : AppTheme.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('weekly', weeklyLabel), seg('alltime', allTimeLabel)],
      ),
    );
  }
}

/// Satu baris peringkat (compact). Top-3 di-highlight dengan medali + tint.
class LeaderboardRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final S s;
  /// 'weekly' | 'alltime' — supaya label top-3 sesuai tab yang aktif.
  final String scope;
  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.s,
    this.scope = 'weekly',
  });

  @override
  Widget build(BuildContext context) {
    final rank = (entry['rank'] as num?)?.toInt() ?? 0;
    final nickname = entry['nickname']?.toString() ?? '—';
    final uid = entry['uid']?.toString() ?? '';
    final gender = entry['gender']?.toString() ?? '';
    final registered = entry['is_registered'] == true;
    final myUid = context.select<AuthProvider, String?>((a) => a.uid);
    final isSelf = uid.isNotEmpty && uid == myUid;

    // TANPA ANGKA: skor/jumlah pesan TIDAK ditampilkan. Angka besar (mis.
    // "557") bikin orang malas menyapa (terkesan "tukang chat"). Peringkat
    // cukup ditandai medali/badge + label netral.
    final topColor = _rankAccent(rank);
    final isTop3 = rank >= 1 && rank <= 3;
    // Border avatar: top-3 pakai warna medali (emas/perak/perunggu); sisanya
    // ikut GENDER (male=biru, female=pink) — sama seperti list Pengguna Online.
    final borderColor = isTop3 ? topColor : GenderAvatar.colorFor(gender);

    return Container(
      color: isTop3
          ? topColor.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 30, child: _RankBadge(rank: rank)),
          const SizedBox(width: 8),
          // Foto profil diselesaikan lewat ProfileAvatar(uid) — `entry['avatar']`
          // dari RPC adalah PATH storage ("avatars/xxx.jpg"), BUKAN base64,
          // jadi decode base64 selalu gagal (dulu foto tak pernah tampil).
          // Tap avatar → buka foto (zoom) ala layar Online.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _zoomAvatar(
              context,
              uid: uid,
              name: nickname,
              ring: borderColor,
            ),
            child: ProfileAvatar(
              uid: uid,
              name: nickname,
              size: 32,
              borderColor: borderColor,
              borderWidth: 1.6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nama bisa di-tap → buka PROFIL user (ada fotonya).
                // Seed dikirim supaya halaman profil langsung tampil isi
                // (tanpa fase loading dulu).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: uid.isEmpty
                      ? null
                      : () => _openProfile(
                          context,
                          uid: uid,
                          nickname: nickname,
                          gender: gender,
                          registered: registered,
                          avatar: entry['avatar']?.toString() ?? '',
                        ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong.copyWith(
                            fontWeight:
                                isTop3 ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (registered) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 13,
                          color: AppTheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  isTop3
                      ? (scope == 'alltime'
                          ? s.topActiveTopLabelAllTime
                          : s.topActiveTopLabelWeekly)
                      : s.topActiveGuestLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: isTop3 ? topColor : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Aksi cepat (bukan diri sendiri): Follow = TEKS, Tambah Teman = IKON.
          if (uid.isNotEmpty && !isSelf) ...[
            const SizedBox(width: 6),
            _FollowTextButton(uid: uid, s: s),
            _AddFriendIconButton(uid: uid, s: s),
          ],
        ],
      ),
    );
  }

  void _openProfile(
    BuildContext context, {
    required String uid,
    required String nickname,
    required String gender,
    required bool registered,
    String avatar = '',
  }) {
    final now = DateTime.now();
    // Foto B64 dari cache (kalau sudah tampil di baris leaderboard) → kirim
    // sebagai avatar seed supaya halaman profil menampilkan FOTO pada frame
    // pertama (anti-kedip "inisial → foto"). Fallback ke path mentah bila
    // belum ter-cache (profil akan memuatnya sendiri).
    final cached = AvatarB64Service.instance.cachedSync(uid);
    final seedAvatar = (cached != null && cached.isNotEmpty) ? cached : avatar;
    final seed = UserModel(
      uid: uid,
      nickname: nickname,
      gender: gender,
      age: 0,
      country: '',
      city: '',
      ipAddress: '',
      status: '',
      avatar: seedAvatar,
      isRegistered: registered,
      loginAt: now,
      createdAt: now,
      lastSeen: now,
    );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => UserInfoScreen(
          userId: uid,
          fallbackName: nickname,
          initialProfile: seed,
        ),
      ),
    );
  }

  /// Buka foto avatar user (fullscreen zoom) — resolve dari cache RAM → disk
  /// → network (pola sama `_zoomUserAvatar` di layar Online). Tap avatar.
  Future<void> _zoomAvatar(
    BuildContext context, {
    required String uid,
    required String name,
    required Color ring,
  }) async {
    Uint8List? bytes;
    if (uid.isNotEmpty) {
      final b64 =
          AvatarB64Service.instance.cachedSync(uid) ??
          AvatarB64Service.instance.cachedSyncIncludeDisk(uid);
      if (b64 != null && b64.isNotEmpty) {
        try {
          bytes = base64Decode(b64);
        } catch (_) {}
      }
      if (bytes == null) {
        try {
          bytes = MediaDiskCache.instance.readSync('avatars/$uid.jpg');
        } catch (_) {}
      }
      if (bytes == null) {
        try {
          bytes = await context.read<StorageProvider>().downloadBytes(
            'avatars/$uid.jpg',
          );
        } catch (_) {}
      }
    }
    if (!context.mounted) return;
    _showAvatarZoom(
      context,
      bytes: bytes,
      ring: ring,
      initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
    );
  }

  void _showAvatarZoom(
    BuildContext context, {
    required Uint8List? bytes,
    required Color ring,
    required String initial,
  }) {
    if (bytes == null && initial.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          cacheWidth: 1080,
                          gaplessPlayback: true,
                        ),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: AppTheme.avatarBg,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppGlyph.xl,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (bytes != null && bytes.isNotEmpty) {
        try {
          PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
        } catch (_) {}
      }
    });
  }
}


/// Tombol FOLLOW berbentuk TEKS ("Ikuti"/"Mengikuti") — hangat, tidak dingin.
class _FollowTextButton extends StatelessWidget {
  final String uid;
  final S s;
  const _FollowTextButton({required this.uid, required this.s});

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialProvider>(
      builder: (ctx, sp, _) {
        final following = sp.isFollowing(uid);
        return Tooltip(
          message: following ? s.btnUnfollow : s.btnFollow,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                if (following) {
                  await sp.unfollow(uid);
                } else {
                  await sp.follow(uid);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: following
                      ? Colors.transparent
                      : AppTheme.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  following ? s.socialFollowing : s.btnFollow,
                  style: AppText.label.copyWith(
                    color: following ? AppTheme.textSecondary : AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tombol TAMBAH TEMAN berbentuk IKON. Status ikut SocialProvider.
class _AddFriendIconButton extends StatelessWidget {
  final String uid;
  final S s;
  const _AddFriendIconButton({required this.uid, required this.s});

  @override
  Widget build(BuildContext context) {
    return Consumer<SocialProvider>(
      builder: (ctx, sp, _) {
        final isFriend = sp.isFriend(uid);
        final pending = sp.isPendingFriendRequest(uid);
        final done = isFriend || pending;
        final tip = isFriend
            ? s.btnFriends
            : (pending ? s.btnFriendRequested : s.btnAddFriend);
        return Tooltip(
          message: tip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: done
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final res = await sp.sendFriendRequest(uid);
                      if (res == 'pending' || res == 'friends') {
                        messenger.showSnackBar(
                          SnackBar(content: Text(s.friendRequestSent)),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(content: Text(s.errGeneric)),
                        );
                      }
                    },
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  isFriend
                      ? Icons.how_to_reg_rounded
                      : (pending
                            ? Icons.schedule_rounded
                            : Icons.person_add_alt_rounded),
                  size: 22,
                  color: done ? AppTheme.textSecondary : AppTheme.primary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _rankAccent(int rank) {
  switch (rank) {
    case 1:
      return const Color(0xFFFFC107); // emas
    case 2:
      return const Color(0xFF9E9E9E); // perak
    case 3:
      return const Color(0xFFCD7F32); // perunggu
    default:
      return AppTheme.primary;
  }
}

/// Badge peringkat: medali utk 1-3, angka utk lainnya.
class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank >= 1 && rank <= 3) {
      return Text(
        rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉',
        style: const TextStyle(fontSize: AppGlyph.md),
        textAlign: TextAlign.center,
      );
    }
    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: AppText.bodySmall.copyWith(
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Bar peringkat-pribadi yang menempel di bawah sheet.
class _MyRankBar extends StatelessWidget {
  final int? rank;
  final double bottomInset;
  const _MyRankBar({
    required this.rank,
    this.bottomInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rank == null
                  ? s.topActiveUnranked
                  : '${s.topActiveYourRank}: #$rank',
              style: AppText.bodyStrong.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
