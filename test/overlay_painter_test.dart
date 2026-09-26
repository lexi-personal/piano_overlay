import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/features/preview/overlay_painter.dart';

/// Rasterises [painter] over a [size] canvas and reports the pixels it touched.
Future<ui.Image> _render(OverlayPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  painter.paint(canvas, size);
  return recorder
      .endRecording()
      .toImage(size.width.toInt(), size.height.toInt());
}

Future<bool> _isPainted(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  return data!.getUint8(offset + 3) != 0;
}

void main() {
  const size = Size(200, 100);

  // A strip that deliberately spills past the left edge of the video, the way
  // a steep camera angle extrapolates the fall lane off frame.
  final strip = NoteStripRenderData(
    quad: const [
      Offset(-60, 10),
      Offset(160, 10),
      Offset(160, 90),
      Offset(-60, 90),
    ],
    color: const Color(0xFFFF0000),
  );

  test('without a clip rect the overlay paints over the whole canvas',
      () async {
    final image = await _render(
      OverlayPainter(strips: [strip], keyHighlights: const []),
      size,
    );
    expect(await _isPainted(image, 5, 50), isTrue);
  });

  test('a clip rect keeps the overlay inside the video frame', () async {
    final image = await _render(
      OverlayPainter(
        strips: [strip],
        keyHighlights: const [],
        clipRect: const Rect.fromLTWH(40, 0, 120, 100),
      ),
      size,
    );

    expect(await _isPainted(image, 5, 50), isFalse,
        reason: 'left panel must stay clean');
    expect(await _isPainted(image, 190, 50), isFalse,
        reason: 'right panel must stay clean');
    expect(await _isPainted(image, 100, 50), isTrue,
        reason: 'the video area still shows the strip');
  });

  test('background dimming is confined to the video frame', () async {
    final image = await _render(
      OverlayPainter(
        strips: const [],
        keyHighlights: const [],
        backgroundDim: 0.5,
        clipRect: const Rect.fromLTWH(40, 0, 120, 100),
      ),
      size,
    );

    expect(await _isPainted(image, 5, 50), isFalse);
    expect(await _isPainted(image, 100, 50), isTrue);
  });
}
