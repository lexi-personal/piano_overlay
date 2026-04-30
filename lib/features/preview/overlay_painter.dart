import 'package:flutter/material.dart';

/// The core overlay painter that renders note strips on top of the video.
/// Consumes pre-computed OverlayFrame data from the shared Rust geometry engine.
///
/// This painter does NOT compute geometry — it only draws the quads/colors/glow
/// that the Rust engine has already computed. This guarantees preview/export parity.
class OverlayPainter extends CustomPainter {
  final List<NoteStripRenderData> strips;
  final List<KeyHighlightRenderData> keyHighlights;
  final double backgroundDim;
  final List<Offset>? fallLaneQuad;
  final double laneOpacity;

  OverlayPainter({
    required this.strips,
    required this.keyHighlights,
    this.backgroundDim = 0.0,
    this.fallLaneQuad,
    this.laneOpacity = 0.55,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Apply background dimming
    if (backgroundDim > 0.0) {
      final dimPaint = Paint()
        ..color = Colors.black.withOpacity(backgroundDim);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), dimPaint);
    }

    // Draw the fall-lane background
    if (fallLaneQuad != null && fallLaneQuad!.length == 4 && laneOpacity > 0) {
      final lanePath = Path()
        ..moveTo(fallLaneQuad![0].dx, fallLaneQuad![0].dy)
        ..lineTo(fallLaneQuad![1].dx, fallLaneQuad![1].dy)
        ..lineTo(fallLaneQuad![2].dx, fallLaneQuad![2].dy)
        ..lineTo(fallLaneQuad![3].dx, fallLaneQuad![3].dy)
        ..close();
      final lanePaint = Paint()
        ..color = Colors.black.withOpacity(laneOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawPath(lanePath, lanePaint);
      // Subtle edge line at keyboard top
      final edgePaint = Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(fallLaneQuad![0], fallLaneQuad![1], edgePaint);
    }

    // Draw key highlights first (below strips)
    for (final highlight in keyHighlights) {
      _drawQuad(canvas, highlight.quad, highlight.color, null, 0);
    }

    // Draw note strips with glow
    for (final strip in strips) {
      if (strip.glowRadius > 0 && strip.glowIntensity > 0) {
        final glowColor = strip.color.withOpacity(strip.color.opacity * strip.glowIntensity * 0.6);
        _drawQuad(canvas, strip.quad, glowColor, strip.glowRadius, 0);
      }
      _drawQuad(canvas, strip.quad, strip.color, null, 0);
    }
  }

  void _drawQuad(Canvas canvas, List<Offset> quad, Color color, double? blurRadius, double elevation) {
    if (quad.length != 4) return;

    final path = Path()
      ..moveTo(quad[0].dx, quad[0].dy)
      ..lineTo(quad[1].dx, quad[1].dy)
      ..lineTo(quad[2].dx, quad[2].dy)
      ..lineTo(quad[3].dx, quad[3].dy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (blurRadius != null && blurRadius > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    // Always repaint when strips change (they change every frame during playback)
    return true;
  }
}

/// Render data for a single note strip (mirrors Rust NoteStrip).
class NoteStripRenderData {
  /// Four screen-space vertices: TL, TR, BR, BL.
  final List<Offset> quad;
  /// Fill color with alpha.
  final Color color;
  /// Glow radius in pixels.
  final double glowRadius;
  /// Glow intensity (0-1).
  final double glowIntensity;

  const NoteStripRenderData({
    required this.quad,
    required this.color,
    this.glowRadius = 0,
    this.glowIntensity = 0,
  });

  /// Parse from JSON (output of Rust ffi_compute_overlay_frame).
  factory NoteStripRenderData.fromJson(Map<String, dynamic> json) {
    final quadData = json['quad'] as List;
    final colorData = json['color'] as List;

    return NoteStripRenderData(
      quad: quadData.map((p) => Offset(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
      )).toList(),
      color: Color.fromRGBO(
        (colorData[0] * 255).round(),
        (colorData[1] * 255).round(),
        (colorData[2] * 255).round(),
        (colorData[3] as num).toDouble(),
      ),
      glowRadius: (json['glow_radius'] as num?)?.toDouble() ?? 0,
      glowIntensity: (json['glow_intensity'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Render data for a key highlight (mirrors Rust KeyHighlight).
class KeyHighlightRenderData {
  final List<Offset> quad;
  final Color color;

  const KeyHighlightRenderData({
    required this.quad,
    required this.color,
  });

  factory KeyHighlightRenderData.fromJson(Map<String, dynamic> json) {
    final quadData = json['quad'] as List;
    final colorData = json['color'] as List;

    return KeyHighlightRenderData(
      quad: quadData.map((p) => Offset(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
      )).toList(),
      color: Color.fromRGBO(
        (colorData[0] * 255).round(),
        (colorData[1] * 255).round(),
        (colorData[2] * 255).round(),
        (colorData[3] as num).toDouble(),
      ),
    );
  }
}

/// Parsed overlay frame from Rust (mirrors Rust OverlayFrame).
class OverlayFrameData {
  final List<NoteStripRenderData> strips;
  final List<KeyHighlightRenderData> keyHighlights;
  final double timestampMs;
  final List<Offset>? fallLaneQuad;

  const OverlayFrameData({
    required this.strips,
    required this.keyHighlights,
    required this.timestampMs,
    this.fallLaneQuad,
  });

  factory OverlayFrameData.fromJson(Map<String, dynamic> json) {
    List<Offset>? quad;
    if (json['fall_lane_quad'] != null) {
      quad = (json['fall_lane_quad'] as List)
          .map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList();
    }
    return OverlayFrameData(
      strips: (json['strips'] as List)
          .map((s) => NoteStripRenderData.fromJson(s))
          .toList(),
      keyHighlights: (json['key_highlights'] as List)
          .map((k) => KeyHighlightRenderData.fromJson(k))
          .toList(),
      timestampMs: (json['timestamp_ms'] as num).toDouble(),
      fallLaneQuad: quad,
    );
  }
}
