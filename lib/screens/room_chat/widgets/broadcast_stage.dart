import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/room_provider.dart';

/// Stage video live broadcast room (inline atau PiP).
///
/// Murni tampilan: seluruh data datang dari [session]; satu-satunya akses
/// global (stop broadcast) lewat Riverpod. Tidak menyentuh state layar induk.
class BroadcastStage extends ConsumerWidget {
  const BroadcastStage({
    super.key,
    required this.session,
    required this.isBroadcaster,
    this.onMinimize,
    this.compact = false,
  });

  final RoomBroadcastSession session;
  final bool isBroadcaster;
  final VoidCallback? onMinimize;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final tiles = <Widget>[];
    if (isBroadcaster && session.localRendererReady) {
      tiles.add(RTCVideoView(session.localRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: true));
    }
    for (final r in session.remoteRenderers.values) {
      if (r.srcObject != null) {
        tiles.add(RTCVideoView(r, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover));
      }
    }
    // fallback single remoteRenderer lama
    if (tiles.isEmpty && !isBroadcaster && session.remoteRenderer.srcObject != null) {
      tiles.add(RTCVideoView(session.remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover));
    }
    return Container(
      height: compact ? double.infinity : 220,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tiles.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 8),
                  Text(s.privateRoomsLiveConnecting,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else if (tiles.length == 1)
            tiles.first
          else
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              children: tiles,
            ),
          Positioned(
            top: 8,
            left: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(s.liveViewerCount(session.viewerCount),
                  style: AppText.micro.copyWith(color: Colors.white)),
            ),
          ),
          // Drag ke bawah di AREA MANA PUN video utk minimize (hanya stage
          // inline, bukan PiP). Double-tap juga minimize.
          if (onMinimize != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) {
                  if (d.primaryDelta != null && d.primaryDelta! > 8) {
                    onMinimize!();
                  }
                },
                onDoubleTap: onMinimize,
                child: const SizedBox.expand(),
              ),
            ),
          if (onMinimize != null)
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white54,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          if (isBroadcaster)
            Positioned(
              bottom: 8,
              right: 10,
              child: Row(children: [
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => session.toggleCamera(),
                  icon: Icon(Icons.videocam_rounded,
                      size: 18,
                      color: session.cameraOn ? null : AppTheme.danger),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => session.switchCamera(),
                  icon: const Icon(Icons.cameraswitch_rounded, size: 18),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier)
                        .stopBroadcast(session.roomId);
                    await session.stop();
                  },
                  icon: const Icon(Icons.stop_circle_rounded,
                      size: 20, color: AppTheme.danger),
                ),
              ]),
            ),
          if (!isBroadcaster)
            Positioned(
              bottom: 8,
              right: 10,
              child: Text(s.viewerCount(session.viewerCount),
                  style: AppText.micro.copyWith(color: Colors.white54)),
            ),
        ],
      ),
    );
  }
}
