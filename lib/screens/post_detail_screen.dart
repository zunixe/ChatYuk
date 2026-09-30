import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/timeline_provider.dart';
import '../widgets/post_card.dart';
import '../core/perf/perf_probe.dart';

/// Detail 1 postingan — dibuka dari tap notifikasi "postingan baru".
/// Memakai ulang PostCard (like/komen/share) supaya perilaku identik feed.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
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
      post = await context.read<TimelineProvider>().getPost(widget.postId);
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
    final s = context.watch<LocaleProvider>().s;
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
