import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/timeline_provider.dart';
import '../widgets/post_card.dart';
import '../core/perf/perf_probe.dart';
import '../config/theme.dart';

/// Detail 1 postingan — dibuka dari tap notifikasi "postingan baru".
/// Memakai ulang PostCard (like/komen/share) supaya perilaku identik feed.
class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  Map<String, dynamic>? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    Map<String, dynamic>? post;
    try {
      post = await ProviderScope.containerOf(context, listen: false).read(timelineProvider.notifier).getPost(widget.postId);
    } catch (_) {
      post = null;
    }
    if (!mounted) return;
    setState(() {
      _post = post;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('PostDetail');
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.titlePostDetail)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.post_add_outlined,
                          size: 40,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.postDetailGone,
                          textAlign: TextAlign.center,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: [
                    PostCard(
                      post: _post!,
                      onDeleted: () {
                        if (mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
    );
  }
}
