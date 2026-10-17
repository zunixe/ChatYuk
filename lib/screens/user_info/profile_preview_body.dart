part of '../user_info_screen.dart';

// ignore_for_file: unused_element

/// ─────────────────────────────────────────────────────────────────
/// Tampilan PROFIL gaya Instagram/WA (hero foto + stats + info + aksi).
/// Data sepenuhnya dari UserInfoScreen (tanpa model baru).
/// ─────────────────────────────────────────────────────────────────
class _PProfileBody extends StatefulWidget {
  final String name;
  final int age;
  final String genderLabel;
  final String country;
  final String presence;
  final bool isOnline;
  final bool verified;
  final Uint8List? avatarBytes;
  final List<UserPhoto> gallery;
  final Uint8List? Function(UserPhoto) galleryBytes;
  final Uint8List? avatarBytesFallback;
  final String initial;
  final List<String> hashtags;
  final String? bio;
  final String location;
  final String userId;
  final int followers;
  final int following;
  final int subscribers;
  final bool isFriend;
  final bool isFriendRequestSent;
  final bool isFollowing;
  final bool isSubscribed;
  final bool isSelf;
  final bool canCall;
  final Object s;
  final void Function(String callType) onCall;
  final VoidCallback onMessage;
  final Future<void> Function() onAddFriend;
  final Future<void> Function() onUnfriend;
  final Future<void> Function() onToggleFollow;
  final Future<void> Function() onSubscribe;
  final Future<void> Function() onCancelFriendRequest;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;
  final void Function(int index) onOpenPhoto;
  final VoidCallback onCopyId;
  final VoidCallback onFollowInfo;
  final int galleryCount;

  const _PProfileBody({
    required this.name,
    required this.age,
    required this.genderLabel,
    required this.country,
    required this.presence,
    required this.isOnline,
    required this.verified,
    required this.avatarBytes,
    required this.gallery,
    required this.galleryBytes,
    required this.avatarBytesFallback,
    required this.initial,
    required this.hashtags,
    required this.bio,
    required this.location,
    required this.userId,
    required this.followers,
    required this.following,
    required this.subscribers,
    required this.isFriend,
    required this.isFriendRequestSent,
    required this.isFollowing,
    required this.isSubscribed,
    required this.isSelf,
    required this.canCall,
    required this.s,
    required this.onCall,
    required this.onMessage,
    required this.onAddFriend,
    required this.onUnfriend,
    required this.onToggleFollow,
    required this.onSubscribe,
    required this.onCancelFriendRequest,
    required this.onFollowersTap,
    required this.onFollowingTap,
    required this.onOpenPhoto,
    required this.onCopyId,
    required this.onFollowInfo,
    required this.galleryCount,
  });

  @override
  State<_PProfileBody> createState() => _PProfileBodyState();
}

class _PProfileBodyState extends State<_PProfileBody> {
  static const double _heroHeight = 440;
  static const double _toolbarHeight = 52;

  final ScrollController _scroll = ScrollController();
  final PageController _pages = PageController();
  late bool _friend = widget.isFriend;
  bool _collapsed = false;
  int _photo = 0;

  /// Sumber foto hero: avatar dulu (bila ada), lalu galeri terbuka.
  List<_HeroItem> get _heroes {
    final out = <_HeroItem>[];
    final av = widget.avatarBytes ?? widget.avatarBytesFallback;
    if (av != null) out.add(_HeroItem.bytes(av));
    for (final p in widget.gallery) {
      final b = widget.galleryBytes(p);
      if (b != null) out.add(_HeroItem.bytes(b));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final c = _scroll.offset > _heroHeight - _toolbarHeight - 24;
    if (c != _collapsed) setState(() => _collapsed = c);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    final n = _heroes.length;
    if (n == 0) return;
    final target = i.clamp(0, n - 1);
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _friendAction() async {
    if (!_friend) {
      if (widget.isFriendRequestSent) {
        await widget.onCancelFriendRequest();
        if (!mounted) return;
        setState(() => _friend = false);
        showProfileToast(context, 'Permintaan dibatalkan');
        return;
      }
      await widget.onAddFriend();
      if (!mounted) return;
      setState(() => _friend = true);
      showProfileToast(context, 'Permintaan pertemanan terkirim');
      return;
    }
    await showPSheet(context, [
      PSheetAction(
        icon: Icons.person_remove_outlined,
        label: 'Putus pertemanan',
        destructive: true,
        onTap: _unfriend,
      ),
    ]);
  }

  Future<void> _unfriend() async {
    final ok = await confirmPUnfriend(context, name: widget.name);
    if (!ok) return;
    await widget.onUnfriend();
    if (!mounted) return;
    setState(() => _friend = false);
    showProfileToast(context, 'Pertemanan diputus');
  }

  void _openMore() {
    showPSheet(context, [
      if (!widget.isSelf)
        PSheetAction(
          icon: widget.isFollowing
              ? Icons.person_remove_alt_1_outlined
              : Icons.person_add_alt_1_outlined,
          label: widget.isFollowing ? 'Berhenti mengikuti' : 'Ikuti',
          onTap: widget.onToggleFollow,
        ),
      if (!widget.isSelf && !widget.isSubscribed)
        PSheetAction(
          icon: Icons.workspace_premium_outlined,
          label: 'Berlangganan',
          onTap: widget.onSubscribe,
        ),
      PSheetAction(
        icon: Icons.help_outline_rounded,
        label: 'Ikuti vs Teman',
        onTap: widget.onFollowInfo,
      ),
      PSheetAction(
        icon: Icons.copy_rounded,
        label: 'Salin User ID',
        onTap: widget.onCopyId,
      ),
      if (!widget.isSelf && widget.canCall)
        PSheetAction(
          icon: Icons.call_outlined,
          label: 'Telepon suara',
          onTap: () => widget.onCall('audio'),
        ),
      if (!widget.isSelf && widget.canCall)
        PSheetAction(
          icon: Icons.videocam_outlined,
          label: 'Telepon video',
          onTap: () => widget.onCall('video'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: _heroHeight,
          toolbarHeight: _toolbarHeight,
          backgroundColor: PColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          titleSpacing: 0,
          shape: _collapsed
              ? const Border(bottom: BorderSide(color: PColors.divider))
              : null,
          leading: Center(
            child: PHeaderButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Kembali',
              solid: _collapsed,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
          title: AnimatedOpacity(
            opacity: _collapsed ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PColors.textStrong,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.verified) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: PColors.accent,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!widget.isSelf && widget.canCall)
              PHeaderButton(
                icon: Icons.call_outlined,
                tooltip: 'Telepon',
                solid: _collapsed,
                onTap: () => widget.onCall('audio'),
              ),
            const SizedBox(width: 8),
            PHeaderButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Opsi lainnya',
              solid: _collapsed,
              onTap: _openMore,
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _buildHero(context),
          ),
        ),
        SliverToBoxAdapter(child: _buildBody(context)),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final heroes = _heroes;
    return LayoutBuilder(
      builder: (context, c) => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTapUp: heroes.length > 1
                  ? (d) => _goTo(
                      d.localPosition.dx < c.maxWidth * 0.4
                          ? _photo - 1
                          : ((_photo + 1) % heroes.length),
                    )
                  : null,
              onTap: heroes.isEmpty
                  ? null
                  : () => widget.onOpenPhoto(
                      _photo.clamp(0, widget.gallery.length - 1),
                    ),
              child: heroes.isEmpty
                  ? PNoPhoto(initials: widget.initial)
                  : PageView.builder(
                      controller: _pages,
                      itemCount: heroes.length,
                      onPageChanged: (i) => setState(() => _photo = i),
                      itemBuilder: (_, i) => Image.memory(
                        heroes[i].bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            PNoPhoto(initials: widget.initial),
                      ),
                    ),
            ),
            const IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.6, 1],
                        colors: [
                          Color(0x000F1115),
                          Color(0xBF0F1115),
                          Color(0xF20F1115),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (heroes.length > 1)
              Positioned(
                left: 12,
                right: 12,
                top: top + _toolbarHeight + 6,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      for (var i = 0; i < heroes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            decoration: BoxDecoration(
                              color: i == _photo
                                  ? Colors.white
                                  : const Color(0x59FFFFFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.age > 0
                                    ? '${widget.name}, ${widget.age}'
                                    : widget.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            if (widget.verified) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.verified_rounded,
                                size: 20,
                                color: PColors.accent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.country.isEmpty
                              ? widget.genderLabel
                              : '${widget.genderLabel} · ${widget.country}',
                          style: const TextStyle(
                            color: Color(0xFFD5D9DE),
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: PColors.scrim,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.isOnline
                                      ? PColors.online
                                      : PColors.offline,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.presence,
                                style: const TextStyle(
                                  color: Color(0xFFD5D9DE),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.galleryCount > 0) ...[
                    const SizedBox(width: 12),
                    PHeaderButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Lihat foto layar penuh',
                      solid: false,
                      iconSize: 18,
                      onTap: () => widget.onOpenPhoto(
                        _photo.clamp(0, widget.gallery.length - 1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: PStatsRow(
            asCard: true,
            stats: [
              PStat(widget.followers, 'Pengikut', onTap: widget.onFollowersTap),
              PStat(widget.following, 'Mengikuti', onTap: widget.onFollowingTap),
              PStat(widget.subscribers, 'Subscriber'),
            ],
          ),
        ),
        if (widget.bio != null && widget.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Text(
              widget.bio!,
              style: const TextStyle(
                color: PColors.text,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ),
        if (widget.hashtags.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Text(
              'Minat',
              style: TextStyle(
                color: PColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in widget.hashtags)
                  PChip(text: t.startsWith('#') ? t : '#$t', height: 30),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: PInfoCard(
            items: [
              if (widget.location.isNotEmpty)
                PInfoItem(
                  icon: Icons.location_on_outlined,
                  value: widget.location,
                  label: 'Kota dan negara',
                ),
              PInfoItem(
                icon: Icons.badge_outlined,
                value: widget.userId,
                label: 'User ID',
                tabular: true,
                trailing: PCopyButton(
                  tooltip: 'Salin User ID',
                  onTap: widget.onCopyId,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Postingan',
                style: TextStyle(
                  color: PColors.textStrong,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        PEmptyState(
          icon: Icons.article_outlined,
          title: 'Belum ada postingan',
          subtitle: 'Postingan ${widget.name} akan muncul di sini.',
        ),
      ],
    );
  }
}

/// Satu foto hero (bytes lokal — tidak ada network di profil ini).
class _HeroItem {
  final Uint8List bytes;
  _HeroItem.bytes(this.bytes);
}
