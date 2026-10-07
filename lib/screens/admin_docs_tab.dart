import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../config/theme.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/search_field.dart';
import 'admin_docs/widgets/user_docs_widgets.dart';
import 'admin_docs/widgets/developer_docs_widgets.dart';
import '../config/strings_docs.dart' show SDocsX;

/// Admin: tab Dokumentasi — panduan fitur (Pengguna) + arsitektur (Developer).
/// Seluruh teks lewat `s.` (bilingual, bukan hardcode).
class AdminDocsTab extends ConsumerStatefulWidget {
  const AdminDocsTab({super.key});

  @override
  ConsumerState<AdminDocsTab> createState() => _AdminDocsTabState();
}

class _AdminDocsTabState extends ConsumerState<AdminDocsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.adminDocsTab, style: AppText.titleEmphasis),
                ),
              ],
            ),
          ),
          SearchField(
            controller: _searchCtrl,
            hint: s.adminDocsSearch,
            onChanged: (v) => setState(() => _query = v),
          ),
          TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            labelStyle: AppText.bodySmall.copyWith(fontWeight: FontWeight.w800),
            unselectedLabelStyle:
                AppText.bodySmall.copyWith(fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: s.adminDocsUser),
              Tab(text: s.adminDocsDeveloper),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DocsScroll(
                  intro: s.adminDocsUserIntro,
                  child: UserDocsList(query: _query),
                ),
                _DocsScroll(
                  intro: s.adminDocsDevIntro,
                  child: DeveloperDocsList(query: _query),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocsScroll extends StatelessWidget {
  final String intro;
  final Widget child;
  const _DocsScroll({required this.intro, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      children: [
        Text(
          intro,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
