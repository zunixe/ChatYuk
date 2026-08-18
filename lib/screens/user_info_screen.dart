import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../models/user_photo.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/social_service.dart';
import '../widgets/async_photo.dart';
import '../providers/theme_provider.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String fallbackName;
  const UserInfoScreen({super.key, required this.userId, required this.fallbackName});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  UserModel? _profile;
  bool _loading = true;
  List<UserPhoto> _photos = [];
  bool _loadingPhotos = true;
  String _status = 'offline';
  StreamSubscription<String>? _statusSub;

  // Status sosial terhadap user ini.
  bool _following = false;
  bool _friend = false;
  bool _friendRequestSent = false;
  bool _subscribed = false;
  bool _busySocial = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPhotos();
    _loadSocial();
    // Ambil nominal biaya buka foto untuk label harga.
    context.read<PointsProvider>().refreshPhotoCosts();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSocial() async {
    try {
      final st = await SocialService().mySocialStatus(widget.userId);
      if (!mounted) return;
      setState(() {
        _following = st['following'] == true;
        _friend = st['friend'] == true;
        _friendRequestSent = st['friend_request_sent'] == true;
        _subscribed = st['subscribed'] == true;
      });
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final s = context.read<LocaleProvider>().s;
    final social = context.read<SocialProvider>();
    setState(() => _busySocial = true);
    final ok = _following
        ? await social.unfollow(widget.userId)
        : await social.follow(widget.userId);
    if (!mounted) return;
    setState(() {
      _following = !_following;
      if (!_following) _friend = false;
      _busySocial = false;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_following ? s.btnFollow : s.btnUnfollow)),
      );
    }
  }

  Future<void> _addFriend() async {
    final s = context.read<LocaleProvider>().s;
    final social = context.read<SocialProvider>();
    setState(() => _busySocial = true);
    final status = await social.sendFriendRequest(widget.userId);
    if (!mounted) return;
    setState(() {
      if (status == 'pending') _friendRequestSent = true;
      _busySocial = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.friendRequestSent)));
  }

  Future<void> _subscribe() async {
    final s = context.read<LocaleProvider>().s;
    final profile = _profile;
    if (profile == null) return;
    final price = profile.subscriptionPrice;
    if (price <= 0) return;
    final auth = context.read<AuthProvider>();
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }
    final points = context.read<PointsProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(children: [
          Icon(Icons.star_rounded, color: Color(0xFFB8860B)),
          SizedBox(width: 8),
          Expanded(child: Text(s.subscribeConfirmTitle)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.subscribeConfirmBody(profile.nickname, price, 1),
                style: AppText.bodyStrong),
            SizedBox(height: 12),
            Text(s.subscribeFansHint,
                style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnSubscribe, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySocial = true);
    try {
      await points.subscribeCreator(widget.userId);
      if (!mounted) return;
      setState(() => _subscribed = true);
      points.refreshWallet();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.subscribeSuccess)));
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('registered') ? s.subscribeNeedRegister
          : msg.contains('Not enough paid') || msg.contains('Not enough') ? s.subscribeNeedPaid
          : s.errGeneric;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(show)));
    } finally {
      if (mounted) setState(() => _busySocial = false);
    }
  }

  /// Subscribe status dengan seed dari profil yang baru di-fetch,
  /// supaya dot status benar sejak frame pertama tanpa query tambahan.
  void _subscribeStatus(UserModel? fresh) {
    _statusSub?.cancel();
    final known = fresh == null
        ? null
        : ChatService.effectiveStatusOf(fresh.status, fresh.lastSeen.toIso8601String());
    _statusSub = context.read<ChatProvider>().getUserStatus(widget.userId, initialStatus: known).listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });
  }

  Future<void> _load() async {
    UserModel? p;
    try {
      p = await AuthService().getProfileById(widget.userId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profile = p;
        _loading = false;
      });
      _subscribeStatus(p);
    }
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await AuthService().getPhotosWithAccess(widget.userId);
      if (mounted) setState(() => _photos = photos);
    } catch (_) {}
    if (mounted) setState(() => _loadingPhotos = false);
  }

  void _showPhotoViewer(List<UserPhoto> photos, int index) {
    // Hanya foto terbuka yang bisa dilihat penuh.
    final unlockedPhotos = photos.where((p) => p.unlocked).toList();
    if (unlockedPhotos.isEmpty) return;
    final target = photos[index];
    final viewerIndex = unlockedPhotos.indexWhere((p) => p.id == target.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _UserPhotoViewer(
          photos: unlockedPhotos,
          initialIndex: viewerIndex < 0 ? 0 : viewerIndex,
        ),
      ),
    );
  }

  /// Tap foto terkunci → bottom sheet pilihan buka (once/perm).
  Future<void> _onLockedTap(UserPhoto photo) async {
    final s = context.read<LocaleProvider>().s;
    final pp = context.read<PointsProvider>();
    final auth = context.read<AuthProvider>();
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.msgVerifyToUsePaid)));
      return;
    }
    final onceCost = pp.photoUnlockOnce;
    final permCost = pp.photoUnlockPerm;
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgScreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 12),
          Icon(Icons.lock_outline, size: 36, color: AppTheme.primary),
          SizedBox(height: 8),
          Text(s.photoLockedTitle, style: AppText.title),
          SizedBox(height: 4),
          Text(s.photoLockedHint, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.visibility_outlined, color: AppTheme.primary),
            title: Text(s.photoUnlockOnce(onceCost)),
            onTap: () => Navigator.pop(ctx, 'once'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_open, color: AppTheme.primary),
            title: Text(s.photoUnlockPerm(permCost)),
            onTap: () => Navigator.pop(ctx, 'perm'),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (mode == null || !mounted) return;
    try {
      final ok = await pp.unlockPhoto(photo.id, mode);
      if (!mounted) return;
      if (ok) {
        if (mode == 'perm') {
          // Reload supaya foto asli ikut terbuka permanen.
          await _loadPhotos();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.photoUnlockedToast)));
        } else {
          // Lihat sekali: ambil foto asli sementara & tampilkan viewer.
          final full = await AuthService().getPhotos(widget.userId);
          if (!mounted) return;
          final match = full.where((p) => p.id == photo.id).toList();
          if (match.isNotEmpty) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _UserPhotoViewer(photos: match, initialIndex: 0),
            ));
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (e == 'topup') {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.photoLockedTitle),
            content: Text(s.photoUnlockNeedTopup),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnClose))],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.photoUnlockFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final profile = _profile;
    final pointsEnabled = context.watch<PointsProvider>().enabled;

    final name = profile?.nickname ?? widget.fallbackName;
    final genderLabel = profile?.gender == 'male'
        ? s.genderLabelMale
        : profile?.gender == 'female'
            ? s.genderLabelFemale
            : s.genderLabelOther;
    final status = _status;
    final statusLabel = status == 'online'
        ? s.statusOnline
        : status == 'idle'
            ? s.statusIdle
            : s.statusOffline;
    final statusColor = status == 'online'
        ? AppTheme.online
        : status == 'idle'
            ? AppTheme.idle
            : AppTheme.textSecondary;

    return Scaffold(
      appBar: AppBar(title: Text(s.titleProfile)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(height: 20),

                  // Avatar
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      (profile?.avatar ?? '').isNotEmpty
                          ? AsyncCircleAvatar(
                              base64: profile!.avatar,
                              radius: 50,
                              bgColor: profile.gender == 'male' ? AppTheme.male : profile.gender == 'female' ? AppTheme.female : AppTheme.accent,
                            )
                          : CircleAvatar(
                              radius: 50,
                              backgroundColor: profile?.gender == 'male'
                                  ? AppTheme.male : profile?.gender == 'female' ? AppTheme.female : AppTheme.accent,
                              child: Text((name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                style: TextStyle(color: Colors.white, fontSize: AppGlyph.avatarInitial(100), fontWeight: FontWeight.w800)),
                            ),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(name, style: AppText.headline.copyWith(color: AppTheme.textPrimary)),
                      ),
                      if (profile?.isRegistered == true) ...[
                        SizedBox(width: 5),
                        Icon(Icons.verified, size: 20, color: Color(0xFF4A90E2)),
                      ],
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(genderLabel, style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary)),
                      if (profile?.age != null && profile!.age > 0) ...[
                        SizedBox(width: 12),
                        Text('${profile.age} ${s.labelYears}', style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary)),
                      ],
                    ],
                  ),
                  SizedBox(height: 24),

                  if (profile != null && profile.hashtags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: profile.hashtags.map((tag) => Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text('#$tag', style: AppText.label.copyWith(letterSpacing: 0)),
                      )).toList(),
                    ),
                    SizedBox(height: 24),
                  ],

                  // Info card
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _infoRow(s.labelStatus, statusLabel),
                          if (profile != null) ...[
                            Divider(color: AppTheme.divider),
                            _infoRow(s.labelCountry, profile.country.isEmpty ? '-' : profile.country),
                            Divider(color: AppTheme.divider),
                            _infoRow(s.labelCity, profile.city.isEmpty ? '-' : profile.city),
                          ],
                          Divider(color: AppTheme.divider),
                          _infoRow(s.labelUserId, widget.userId.substring(0, 8)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Sosial: angka + tombol Follow / Friend / Subscribe
                  if (profile != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Stats bar — angka + label + ikon, terpisah rapi.
                          Padding(
                            padding: EdgeInsets.fromLTRB(8, 18, 8, 16),
                            child: Row(
                              children: [
                                _statColumn(
                                  icon: Icons.favorite_rounded,
                                  color: Color(0xFFE91E63),
                                  value: profile.followersCount,
                                  label: s.socialFollowers,
                                ),
                                _statDivider(),
                                _statColumn(
                                  icon: Icons.person_rounded,
                                  color: AppTheme.primary,
                                  value: profile.followingCount,
                                  label: s.socialFollowing,
                                ),
                                _statDivider(),
                                _statColumn(
                                  icon: Icons.star_rounded,
                                  color: Color(0xFFB8860B),
                                  value: profile.subscriberCount,
                                  label: s.socialSubscribers,
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, indent: 16, endIndent: 16),
                          Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              children: [
                                // Baris tombol aksi utama: Follow + Friend.
                                Row(
                                  children: [
                                    Expanded(
                                      child: _SocialActionButton(
                                        active: _following,
                                        activeIcon: Icons.check_rounded,
                                        activeLabel: s.btnUnfollow,
                                        activeColor: AppTheme.textSecondary,
                                        icon: Icons.person_add_alt_1_rounded,
                                        label: s.btnFollow,
                                        color: AppTheme.primary,
                                        loading: _busySocial,
                                        onTap: _toggleFollow,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: _friend
                                          ? _SocialActionButton(
                                              active: true,
                                              activeIcon: Icons.group_rounded,
                                              activeLabel: s.btnFriends,
                                              activeColor: Colors.green,
                                              icon: Icons.group_add_rounded,
                                              label: s.btnFriends,
                                              color: Colors.green,
                                              loading: false,
                                              onTap: () {},
                                            )
                                          : _friendRequestSent
                                              ? _SocialActionButton(
                                                  active: true,
                                                  activeIcon: Icons.schedule_rounded,
                                                  activeLabel: s.btnFriendRequested,
                                                  activeColor: Colors.orange,
                                                  icon: Icons.group_add_rounded,
                                                  label: s.btnFriendRequested,
                                                  color: Colors.orange,
                                                  loading: false,
                                                  onTap: () {},
                                                )
                                              : _SocialActionButton(
                                                  active: false,
                                                  icon: Icons.group_add_rounded,
                                                  label: s.btnAddFriend,
                                                  color: Colors.green,
                                                  loading: _busySocial,
                                                  onTap: _addFriend,
                                                ),
                                    ),
                                  ],
                                ),
                                if (pointsEnabled && profile.subscriptionPrice > 0) ...[
                                  SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _subscribed
                                        ? _SocialActionButton(
                                            active: true,
                                            activeIcon: Icons.star_rounded,
                                            activeLabel: s.btnSubscribed,
                                            activeColor: Color(0xFFB8860B),
                                            icon: Icons.star_rounded,
                                            label: s.btnSubscribed,
                                            color: Color(0xFFB8860B),
                                            loading: false,
                                            onTap: () {},
                                          )
                                        : _SocialActionButton(
                                            active: false,
                                            icon: Icons.star_rounded,
                                            label: '${s.btnSubscribe} · ${s.subscribePrice(profile.subscriptionPrice)}',
                                            color: Color(0xFFB8860B),
                                            loading: _busySocial,
                                            onTap: _subscribe,
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                  ],

                  // Galeri Foto Profil
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.labelOthersGallery, style: AppText.titleEmphasis),
                          SizedBox(height: 8),
                          if (_loadingPhotos)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                            )
                          else if (_photos.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: Text(s.labelGalleryEmpty, textAlign: TextAlign.center, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary))),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                              itemCount: _photos.length,
                              itemBuilder: (ctx, i) {
                                final photo = _photos[i];
                                if (photo.unlocked) {
                                  return GestureDetector(
                                    onTap: () => _showPhotoViewer(_photos, i),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: AsyncPhotoThumbnail(base64: photo.photo),
                                    ),
                                  );
                                }
                                // Terkunci: preview blur + overlay gelap + gembok + harga.
                                return GestureDetector(
                                  onTap: () => _onLockedTap(photo),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (photo.preview.isNotEmpty)
                                          ImageFiltered(
                                            imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                            child: AsyncPhotoThumbnail(base64: photo.preview),
                                          )
                                        else
                                          Container(color: AppTheme.bgCard),
                                        Container(color: Colors.black.withValues(alpha: 0.35)),
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.lock, color: Colors.white, size: 24),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '${context.read<PointsProvider>().photoUnlockOnce} 🪙',
                                                style: AppText.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSecondary)),
          Text(value, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _statColumn({
    required IconData icon,
    required Color color,
    required int value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          SizedBox(height: 6),
          Text(
            '$value',
            style: AppText.titleEmphasis.copyWith(color: AppTheme.textPrimary),
          ),
          SizedBox(height: 1),
          Text(
            label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 38,
      color: AppTheme.divider,
    );
  }
}

class _SocialActionButton extends StatelessWidget {
  final bool active;
  final bool loading;
  final IconData icon;
  final String label;
  final Color color;
  final IconData? activeIcon;
  final String? activeLabel;
  final Color? activeColor;
  final VoidCallback onTap;
  const _SocialActionButton({
    required this.active,
    required this.loading,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.activeIcon,
    this.activeLabel,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = active;
    final iconData = isActive ? (activeIcon ?? icon) : icon;
    final labelText = isActive ? (activeLabel ?? label) : label;
    final bg = isActive ? (activeColor ?? color) : color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 46,
      decoration: BoxDecoration(
        color: isActive ? bg.withValues(alpha: 0.14) : bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? bg.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isActive ? bg : Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconData,
                        size: 18,
                        color: isActive ? bg : Colors.white,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            labelText,
                            maxLines: 1,
                            style: AppText.bodySmall.copyWith(
                              color: isActive ? bg : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _UserPhotoViewer extends StatefulWidget {
  final List<UserPhoto> photos;
  final int initialIndex;
  const _UserPhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_UserPhotoViewer> createState() => _UserPhotoViewerState();
}

class _UserPhotoViewerState extends State<_UserPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.photos.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) => Center(
          child: InteractiveViewer(
            maxScale: 4,
            child: AsyncPhotoViewer(base64: widget.photos[i].photo),
          ),
        ),
      ),
    );
  }
}
