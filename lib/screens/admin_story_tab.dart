import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/story_provider.dart';
import '../widgets/filter_chip_pill.dart';
import 'admin_story_viewer_screen.dart';
import '../providers/riverpod/admin_provider.dart';

/// Tab admin: kelola STORY user.
///
/// Grid 3 kolom (ukuran kartu = thumbnail story, rasio ~0.57), satu layar,
/// scroll atas-bawah — terbaru di atas (server urut created_at desc). Tiap
/// kartu diberi WARNA + ikon sesuai visibilitas (public/pengikut/teman/
/// private). Tap kartu → viewer fullscreen (lihat seperti story biasa) +
/// info "terlihat oleh" + panel atur visibilitas + hapus permanen.
class AdminStoryTab extends ConsumerStatefulWidget {
  const AdminStoryTab({super.key});

  @override
  ConsumerState<AdminStoryTab> createState() => _AdminStoryTabState();
}

class _AdminStoryTabState extends ConsumerState<AdminStoryTab> {
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    // Muat saat pertama tab dibuka (lazy).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ProviderScope.containerOf(context, listen: false).read(adminProvider).fetchStories();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild HANYA saat domain story berubah (bukan polling domain lain).
    ref.watch(adminProvider.select((p) => p.revStories));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final stories = admin.stories;
    final loading = admin.storiesLoading;
    final filter = admin.storyFilter;

    return Column(
      children: [
        // Sub-judul + bar filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.adminStorySubtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              IconButton(
                tooltip: s.btnRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => admin.fetchStories(force: true),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final (key, label, color) in [
                ('all', s.adminStoryFilterAll, AppTheme.primary),
                ('public', s.adminStoryFilterPublic, AppTheme.online),
                ('followers', s.adminStoryFilterFollowers, AppTheme.accent),
                ('friends', s.adminStoryFilterFriends, AppTheme.female),
                ('private', s.adminStoryFilterPrivate, AppTheme.danger),
              ]) ...[
                FilterChipPill(
                  label: label,
                  color: color,
                  active: filter == key,
                  onTap: () => admin.setStoryFilter(key),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading && stories.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : stories.isEmpty
              ? Center(
                  child: Text(
                    s.adminStoryEmpty,
                    style: AppText.body.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.fetchStories(force: true),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      // Rasio kartu = thumbnail story (67×114 ≈ 0.588).
                      childAspectRatio: 0.62,
                    ),
                    itemCount: stories.length,
                    itemBuilder: (_, i) {
                      final it = stories[i];
                      return _StoryAdminCard(
                        key: ValueKey('${it['id']}'),
                        item: it,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminStoryViewerScreen(
                              stories: stories,
                              initialIndex: i,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Warna + ikon + label untuk state visibilitas.
({Color color, IconData icon, String key}) storyVisStyle(
  Map<String, dynamic> m,
  S s,
) {
  final ownerOnly = m['owner_only'] == true;
  if (ownerOnly) {
    return (color: AppTheme.danger, icon: Icons.lock, key: 'private');
  }
  switch ('${m['visibility']}') {
    case 'friends':
      return (color: AppTheme.female, icon: Icons.favorite_rounded, key: 'friends');
    case 'followers':
      return (color: AppTheme.accent, icon: Icons.group_rounded, key: 'followers');
    default:
      return (color: AppTheme.online, icon: Icons.public, key: 'public');
  }
}

class _StoryAdminCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _StoryAdminCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final style = storyVisStyle(item, s);
    final thumb = '${item['image_path'] ?? ''}';
    final name = '${item['author_name'] ?? 'Anon'}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: style.color, width: 2),
          color: AppTheme.bgCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StoryThumb(path: thumb),
            // Gradasi bawah untuk keterbacaan nama.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.6, 1.0],
                ),
              ),
            ),
            // Badge visibilitas (kiri atas) — warna = status.
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: style.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, size: 12, color: Colors.white),
              ),
            ),
            // Nama author (bawah).
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.micro.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail story (cache provider, transform server — ringan).
class _StoryThumb extends StatefulWidget {
  final String path;
  const _StoryThumb({required this.path});

  @override
  State<_StoryThumb> createState() => _StoryThumbState();
}

class _StoryThumbState extends State<_StoryThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StoryThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final p = widget.path;
    if (p.isEmpty) return;
    final sp = ProviderScope.containerOf(context, listen: false).read(storyProvider.notifier);
    // Cache RAM dulu (sinkron) → frame pertama langsung terisi.
    final cached = sp.thumbCached(p);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    final b = await sp.thumbFor(p);
    if (mounted && b != null) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return Container(
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      b,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Kartu grid ~3 kolom → cap decode kecil (hemat memori).
      cacheWidth: 200,
    );
  }
}
