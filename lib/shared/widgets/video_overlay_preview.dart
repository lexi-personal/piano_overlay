import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../services/project_provider.dart';
import '../overlay_geometry.dart';
import '../../features/preview/overlay_painter.dart';

/// Shared widget that displays video with the MIDI overlay on top.
/// Used by workspace, sync screen, and preview screen.
class VideoOverlayPreview extends StatelessWidget {
  final ProjectProvider provider;
  final VideoController videoController;
  final Duration position;

  const VideoOverlayPreview({
    super.key,
    required this.provider,
    required this.videoController,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(child: Video(controller: videoController)),
        if (provider.hasCalibration && provider.hasMidi)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  painter: _buildPainter(constraints.biggest),
                );
              },
            ),
          ),
      ],
    );
  }

  OverlayPainter _buildPainter(Size size) {
    final project = provider.project!;
    final cal = project.calibration!;
    final style = project.style;
    final sync = project.sync;
    final posMs = position.inMilliseconds.toDouble();

    final frameData = OverlayGeometry.computeFrame(
      calibration: cal,
      notes: project.midi?.allNotes ?? [],
      style: style,
      sync: sync,
      timestampMs: posMs,
      displayWidth: size.width,
      displayHeight: size.height,
      calibrationWidth: cal.calibrationWidth > 0 ? cal.calibrationWidth : null,
      calibrationHeight: cal.calibrationHeight > 0 ? cal.calibrationHeight : null,
    );

    return OverlayPainter(
      strips: frameData.strips,
      keyHighlights: frameData.keyHighlights,
      backgroundDim: style.backgroundDim,
      fallLaneQuad: frameData.fallLaneQuad,
      laneOpacity: style.laneOpacity,
    );
  }
}
