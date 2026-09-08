import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../providers/locale_provider.dart';
import '../services/storage_photo_service.dart';
import '../widgets/post_photo_viewer.dart';

/// Galeri media grup ala WA: grid foto dari pesan room + viewer.
/// Dibuka dari menu ⋮ grup atau layar info grup.
class GroupMediaScreen extends StatefulWidget {
  final RoomModel room;
  const GroupMediaScreen({super.key, required this.room});

  @override
  State<GroupMediaScreen> createState() => _GroupMediaScreenState();
}

class _GroupMediaScreenState extends State<GroupMediaScreen> {
  List<String> _paths = [];
  final Map<String, Uint8List?> _thumbs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('messages')
          .select('image_path')
          .eq('room_id', widget.room.id)
          .neq('image_path', '')
          .order('inserted_at', ascending: false)
          .limit(200);
      final paths = <String>[];
      for (final r in (rows as List)) {
        final p = '${(r as Map)['image_path'] ?? ''}';
        if (p.isNotEmpty && !paths.contains(p)) paths.add(p);
      }
      if (!mounted) return;
      setState(() {
        _paths = paths;
        _loading = false;
      });
      for (final p in paths) {
        StoragePhotoService.instance.downloadThumbBytes(p).then((b) {
          if (mounted && b != null && b.isNotEmpty) {
            setState(() => _thumbs[p] = b);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(int index) {
    final thumbs = _paths
        .map((p) => _thumbs[p] ?? Uint8List(0))
        .toList(growable: false);
    PostPhotoViewer.show(
      context,
      paths: _paths,
      thumbs: thumbs,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.menuGroupMedia, style: AppText.title),
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : _paths.isEmpty
              ? Center(
                  child: Text(s.groupMediaEmpty,
                      style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _paths.length,
                  itemBuilder: (_, i) {
                    final t = _thumbs[_paths[i]];
                    return GestureDetector(
                      onTap: () => _open(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: t != null && t.isNotEmpty
                            ? Image.memory(t,
                                fit: BoxFit.cover, gaplessPlayback: true)
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
    );
  }
}
