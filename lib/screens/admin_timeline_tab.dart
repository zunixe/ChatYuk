import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/theme.dart';
import '../providers/riverpod/admin_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../widgets/filter_chip_pill.dart';
import '../widgets/post_card.dart';

/// Tab admin: kelola TIMELINE user.
///
/// Menampilkan SELURUH post lintas user (public/followers/subscribers) — TANPA
/// batas RLS `posts_select` (lewat RPC admin `admin_timeline_all`). Kartu
/// memakai [PostCard] yang SAMA dengan Timeline utama (behaviour identik:
/// like/komentar/zoom foto/preview link), plus aksi admin: ubah visibilitas.
///
/// Filter: semua / public / pengikut / subscriber. Terbaru di atas (server).
class AdminTimelineTab extends ConsumerStatefulWidget {
  const AdminTimelineTab({super.key});

  @override
  ConsumerState<AdminTimelineTab> createState() => _AdminTimelineTabState();
}

class _AdminTimelineTabState extends ConsumerState<AdminTimelineTab> {
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .read(adminProvider)
            .fetchPosts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild HANYA saat domain timeline berubah (bukan polling domain lain).
    ref.watch(adminProvider.select((p) => p.revPosts));
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ref.read(localeProvider).s;
    final posts = admin.adminPosts;
    final loading = admin.postsLoading;
    final filter = admin.postFilter;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.adminTimelineSubtitle,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              IconButton(
                tooltip: s.btnRefresh,
                onPressed: () => admin.fetchPosts(force: true),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              FilterChipPill(
                label: s.adminTimelineFilterAll,
                active: filter == 'all',
                onTap: () => admin.setPostFilter('all'),
              ),
              FilterChipPill(
                label: s.adminTimelineFilterPublic,
                active: filter == 'public',
                onTap: () => admin.setPostFilter('public'),
              ),
              FilterChipPill(
                label: s.adminTimelineFilterFollowers,
                active: filter == 'followers',
                onTap: () => admin.setPostFilter('followers'),
              ),
              FilterChipPill(
                label: s.adminTimelineFilterSubscribers,
                active: filter == 'subscribers',
                onTap: () => admin.setPostFilter('subscribers'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: loading && posts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : posts.isEmpty
              ? Center(
                  child: Text(
                    s.adminTimelineEmpty,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.fetchPosts(force: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final post = posts[i];
                      return RepaintBoundary(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _visibilityBar(post, s),
                            PostCard(
                              key: ValueKey('admin-${post['id']}'),
                              post: post,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Bar aksi admin di atas tiap kartu: label visibilitas saat ini + tombol
  /// ubah (public / pengikut / subscriber). Warna sesuai state.
  Widget _visibilityBar(Map<String, dynamic> post, S s) {
    final pid = '${post['id']}';
    final vis = '${post['visibility'] ?? 'public'}';
    final color = vis == 'public'
        ? AppTheme.primary
        : (vis == 'followers' ? Colors.orange : Colors.purple);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          Icon(
            vis == 'public'
                ? Icons.public
                : (vis == 'followers'
                    ? Icons.people_outline_rounded
                    : Icons.star_outline_rounded),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            s.adminTimelineVisLabel(vis),
            style: AppText.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _openVisibilitySheet(pid, vis, s),
            icon: const Icon(Icons.edit, size: 14),
            label: Text(s.adminTimelineSetVisibility),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openVisibilitySheet(String postId, String current, S s) async {
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  s.adminTimelineSetVisibility,
                  style: AppText.titleEmphasis,
                ),
              ),
            ),
            for (final opt in const ['public', 'followers', 'subscribers'])
              ListTile(
                leading: Icon(
                  opt == 'public'
                      ? Icons.public
                      : (opt == 'followers'
                          ? Icons.people_outline_rounded
                          : Icons.star_outline_rounded),
                  color: opt == current ? AppTheme.primary : null,
                ),
                title: Text(s.adminTimelineVisLabel(opt)),
                trailing: opt == current
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    final ok = await admin.setPostVisibility(postId, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? s.adminTimelineVisibilityUpdated : s.msgServerError,
        ),
      ),
    );
  }
}
