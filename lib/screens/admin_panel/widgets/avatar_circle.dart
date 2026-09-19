import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../providers/avatar_provider.dart';

class AdminAvatarCircle extends StatefulWidget {
  final String uid;
  final String name;
  final Color color;
  const AdminAvatarCircle({
    required this.uid,
    required this.name,
    required this.color,
  });

  @override
  State<AdminAvatarCircle> createState() => AdminAvatarCircleState();
}

class AdminAvatarCircleState extends State<AdminAvatarCircle> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid.isEmpty) return;
    try {
      final b64 = await context.read<AvatarProvider>().get(widget.uid);
      if (!mounted || b64.isEmpty) return;
      setState(() => _bytes = base64Decode(b64));
    } catch (_) {}
  }

  void _zoom() {
    final bytes = _bytes;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: widget.color,
                        child: Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppGlyph.xl,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _zoom,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _bytes != null
              ? Colors.transparent
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _bytes != null
              ? Image.memory(_bytes!, fit: BoxFit.cover)
              : Center(
                  child: Text(
                    widget.name.isNotEmpty
                        ? widget.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: AppGlyph.avatarInitial(34),
                      color: widget.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
