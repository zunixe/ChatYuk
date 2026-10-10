import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../config/theme.dart';

/// Sheet pencarian pesan dalam room. Query langsung ke Supabase (`messages`),
/// debounce 350ms, tap hasil → [onJump] dengan id pesan.
Future<void> showRoomSearchSheet(
  BuildContext context, {
  required String roomId,
  required S s,
  required void Function(String id) onJump,
}) async {
  final qCtrl = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool searching = false;
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> doSearch(String q) async {
          final query = q.trim();
          if (query.length < 2) {
            setSheet(() => results = []);
            return;
          }
          setSheet(() => searching = true);
          try {
            final rows = await Supabase.instance.client
                .from('messages')
                .select('id,text,sender_name,sender_id,created_at')
                .eq('room_id', roomId)
                .ilike('text', '%$query%')
                .order('created_at', ascending: false)
                .limit(30);
            if (ctx.mounted) {
              setSheet(() {
                results = (rows as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                searching = false;
              });
            }
          } catch (_) {
            if (ctx.mounted) setSheet(() => searching = false);
          }
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: TextField(
                    autofocus: true,
                    style:
                        AppText.body.copyWith(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                      hintText: s.roomSearchHint,
                    ),
                    onChanged: (q) {
                      // Debounce: guard sheet tertutup dulu, baru sentuh
                      // controller (setelah dispose = exception).
                      Future.delayed(
                          const Duration(milliseconds: 350), () {
                        if (!ctx.mounted) return;
                        if (qCtrl.text != q) return;
                        doSearch(q);
                      });
                    },
                  ),
                ),
                if (searching)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                else if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(s.roomSearchEmpty,
                        style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary)),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return ListTile(
                          dense: true,
                          title: Text('${r['text'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.bodySmall),
                          subtitle: Text(
                              '${r['sender_name'] ?? '?'}',
                              style: AppText.caption.copyWith(
                                  color: AppTheme.textSecondary)),
                          onTap: () {
                            Navigator.pop(ctx);
                            onJump('${r['id'] ?? ''}');
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  qCtrl.dispose();
}
