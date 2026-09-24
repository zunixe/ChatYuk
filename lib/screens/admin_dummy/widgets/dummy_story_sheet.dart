import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils.dart';
import 'section_card.dart';

/// Sheet riwayat story harian dummy (biasa). Menampilkan N hari terakhir
/// + status terisi/kosong supaya ketahuan hari mana yang belum
/// ke-generate. Expert tidak punya story (server tak generate).
void showDummyStorySheet(
  BuildContext context,
  Map<String, dynamic> item,
  S s,
) {
  final nickname = item['nickname'] as String? ?? '';
  final uid = item['uid'] as String? ?? '';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => DummyStorySheet(
          uid: uid,
          nickname: nickname,
          s: s,
          scrollCtrl: scrollCtrl,
        ),
      );
    },
  );
}

/// Isi sheet story: fetch sekali di initState (tidak refetch tiap rebuild),
/// tombol generate me-refresh daftar di tempat.
class DummyStorySheet extends StatefulWidget {
  final String uid;
  final String nickname;
  final S s;
  final ScrollController scrollCtrl;
  const DummyStorySheet({
    super.key,
    required this.uid,
    required this.nickname,
    required this.s,
    required this.scrollCtrl,
  });

  @override
  State<DummyStorySheet> createState() => _DummyStorySheetState();
}

class _DummyStorySheetState extends State<DummyStorySheet> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AdminProvider>().getDummyStories(
          widget.uid,
          days: 14,
        );
  }

  void _refresh() {
    setState(() {
      _future = context.read<AdminProvider>().getDummyStories(
            widget.uid,
            days: 14,
          );
    });
  }

  Future<void> _generate(String storyDate) async {
    final s = widget.s;
    if (widget.uid.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.dummyStoryGenerating)),
    );
    try {
      final result = await context.read<AdminProvider>().generateDummyStory(
            widget.uid,
            storyDate: storyDate,
          );
      if (!mounted) return;
      final generated = (result['generated'] as List?)?.contains(widget.uid) == true;
      final skipped = (result['skipped'] as List?)?.contains(widget.uid) == true;
      final failed = (result['failed'] as List?)?.contains(widget.uid) == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (generated || skipped) && !failed
                ? s.dummyStoryGenerated
                : s.dummyStoryGenerateFail,
          ),
        ),
      );
      if (generated || skipped) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.dummyStoryGenerateFail)),
      );
      dlog('[ADMIN] generate dummy story error: $e');
    }
  }

  /// Ringkas story (jsonb) jadi satu kalimat untuk ditampilkan.
  String _storySummary(dynamic story) {
    if (story is String) return story;
    if (story is Map) {
      for (final k in ['summary', 'work', 'place', 'problem', 'hangout']) {
        final v = story[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return story.values
          .whereType<String>()
          .where((v) => v.trim().isNotEmpty)
          .join(' · ');
    }
    return '$story';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (ctx, snap) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_stories_outlined,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.dummyStoryList} — ${widget.nickname}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (snap.data?['story_expected'] == false)
                        ? s.dummyStoryNotExpected
                        : s.dummyStoryListDesc,
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : snap.hasError
                      ? Center(
                          child: Text(
                            '${s.dummyStoryLoadFail}: ${snap.error}',
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.danger,
                            ),
                          ),
                        )
                      : _storyList(
                          snap.data ?? const {},
                          s,
                          widget.scrollCtrl,
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _storyList(
    Map<String, dynamic> data,
    S s,
    ScrollController scrollCtrl,
  ) {
    final days = (data['days'] as List?) ?? const [];
    if (days.isEmpty) {
      return Center(
        child: Text(s.dummyStoryEmpty, style: AppText.bodySmall),
      );
    }
    final missing =
        days.where((d) => (d as Map)['has_story'] != true).length;
    return ListView.separated(
      controller: scrollCtrl,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: days.length + 1,
      separatorBuilder: (_, i) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i == 0) {
          if (missing == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.dummyStoryMissingCount.replaceAll('%s', '$missing'),
                    style: AppText.caption.copyWith(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
          );
        }
        final d = Map<String, dynamic>.from(days[i - 1] as Map);
        final has = d['has_story'] == true;
        final story = d['story'];
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    has ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: has ? AppTheme.primary : AppTheme.danger,
                  ),
                  const SizedBox(width: 8),
                   Text('${d['date']}', style: AppText.bodyStrong),
                   const Spacer(),
                   if (!has)
                     IconButton(
                       icon: Icon(
                         Icons.auto_awesome,
                         size: 18,
                         color: AppTheme.primary,
                       ),
                       tooltip: s.dummyStoryGenerate,
                       onPressed: () => _generate('${d['date']}'),
                     ),
                   Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (has ? AppTheme.primary : AppTheme.danger)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      has ? s.dummyStoryFilled : s.dummyStoryMissing,
                      style: AppText.caption.copyWith(
                        color: has ? AppTheme.primary : AppTheme.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (has && story != null) ...[
                const SizedBox(height: 6),
                Text(
                  _storySummary(story),
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
