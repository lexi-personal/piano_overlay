import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/models/calibration.dart';
import 'package:piano_overlay/models/midi_note.dart';
import 'package:piano_overlay/models/overlay_style.dart';
import 'package:piano_overlay/features/preview/overlay_painter.dart';
import 'package:piano_overlay/shared/overlay_geometry.dart';

/// A flat, head-on keyboard so expectations stay easy to reason about.
CalibrationData _calibration() => const CalibrationData(
      corners: KeyboardCorners(
        topLeft: Point2D(0, 400),
        topRight: Point2D(520, 400),
        bottomRight: Point2D(520, 480),
        bottomLeft: Point2D(0, 480),
      ),
      keyboardSize: KeyboardSize.keys88,
      homography: [
        [10.0, 0.0, 0.0],
        [0.0, 80.0, 400.0],
        [0.0, 0.0, 1.0],
      ],
      keyPositions: [],
      calibrationWidth: 520,
      calibrationHeight: 480,
    );

const _note = MidiNote(
  pitch: 60,
  velocity: 100,
  startMs: 1000,
  durationMs: 500,
  channel: 0,
  track: 0,
);

OverlayFrameData _frame(OverlayStyle style, {List<MidiNote>? notes}) =>
    OverlayGeometry.computeFrame(
      timestampMs: 0,
      notes: notes ?? const [_note],
      calibration: _calibration(),
      style: style,
      sync: const SyncSettings(),
      displayWidth: 520,
      displayHeight: 480,
    );

double _width(NoteStripRenderData strip) =>
    (strip.quad[2] - strip.quad[3]).distance;

double _centreX(NoteStripRenderData strip) =>
    strip.quad.map((p) => p.dx).reduce((a, b) => a + b) / strip.quad.length;

/// Centre of the strip drawn for [pitch], in display pixels.
double _keyCentre(int pitch) {
  final frame = _frame(
    const OverlayStyle(),
    notes: [
      MidiNote(
        pitch: pitch,
        velocity: 100,
        startMs: 1000,
        durationMs: 500,
        channel: 0,
        track: 0,
      ),
    ],
  );
  return _centreX(frame.strips.single);
}

void main() {
  group('strip shape', () {
    test('strip width follows the thickness slider', () {
      final thin = _frame(const OverlayStyle(stripThickness: 0.5));
      final thick = _frame(const OverlayStyle(stripThickness: 1.0));

      expect(_width(thick.strips.first),
          greaterThan(_width(thin.strips.first) * 2 - 0.5));
      expect(_width(thick.strips.first),
          lessThan(_width(thin.strips.first) * 2 + 0.5));
    });

    test('the default thickness keeps the historical white key width', () {
      final frame = _frame(const OverlayStyle());
      // 0.9 canonical units across a 10px-per-unit keyboard.
      expect(_width(frame.strips.first), closeTo(9.0, 0.01));
    });

    test('corner radius and border scale with the strip width', () {
      final frame = _frame(const OverlayStyle(
        cornerRadius: 0.25,
        borderWidth: 0.1,
      ));
      final strip = frame.strips.first;

      expect(strip.cornerRadius, closeTo(_width(strip) * 0.25, 0.01));
      expect(strip.borderWidth, closeTo(_width(strip) * 0.1, 0.01));
    });

    test('square strips report no rounding or outline', () {
      final strip = _frame(const OverlayStyle()).strips.first;
      expect(strip.cornerRadius, 0);
      expect(strip.borderWidth, 0);
    });
  });

  group('visibility', () {
    test('upcoming notes are hidden when show before play is off', () {
      expect(_frame(const OverlayStyle()).strips, isNotEmpty);
      expect(
        _frame(const OverlayStyle(showBeforePlay: false)).strips,
        isEmpty,
      );
    });

    test('sounding notes are hidden when show during play is off', () {
      const sounding = MidiNote(
        pitch: 60,
        velocity: 100,
        startMs: -100,
        durationMs: 500,
        channel: 0,
        track: 0,
      );

      expect(
        _frame(const OverlayStyle(), notes: const [sounding]).strips,
        isNotEmpty,
      );
      expect(
        _frame(const OverlayStyle(showDuringPlay: false),
                notes: const [sounding])
            .strips,
        isEmpty,
      );
    });
  });

  group('fall direction', () {
    test('top to bottom puts the lane above the keyboard', () {
      final frame = _frame(const OverlayStyle());
      final strip = frame.strips.first;
      // The far end of the strip is higher on screen than the near end.
      expect(strip.quad[0].dy, lessThan(strip.quad[3].dy));
    });

    test('bottom to top puts the lane below the keyboard', () {
      final frame = _frame(
        const OverlayStyle(fallDirection: FallDirection.bottomToTop),
      );
      final strip = frame.strips.first;
      expect(strip.quad[0].dy, greaterThan(strip.quad[3].dy));
    });
  });

  group('colors', () {
    test('hand colors replace the white and black key colors', () {
      const left = MidiNote(
        pitch: 60,
        velocity: 100,
        startMs: 1000,
        durationMs: 500,
        channel: 0,
        track: 0,
      );
      const right = MidiNote(
        pitch: 62,
        velocity: 100,
        startMs: 1000,
        durationMs: 500,
        channel: 0,
        track: 1,
      );

      final frame = _frame(
        const OverlayStyle(
          useHandColors: true,
          leftHandColor: Color(0xFF00FF00),
          rightHandColor: Color(0xFFFF0000),
          transparency: 1.0,
        ),
        notes: const [left, right],
      );

      expect(frame.strips[0].color.value, const Color(0xFF00FF00).value);
      expect(frame.strips[1].color.value, const Color(0xFFFF0000).value);
    });
  });

  group('display mapping', () {
    test('fitVideoRect letterboxes a wide video inside a square box', () {
      final rect = OverlayGeometry.fitVideoRect(
        container: const Size(400, 400),
        videoWidth: 1920,
        videoHeight: 1080,
      );

      expect(rect.width, closeTo(400, 0.001));
      expect(rect.height, closeTo(225, 0.001));
      expect(rect.left, closeTo(0, 0.001));
      expect(rect.top, closeTo(87.5, 0.001));
    });

    test('fitVideoRect pillarboxes a tall video inside a square box', () {
      final rect = OverlayGeometry.fitVideoRect(
        container: const Size(400, 400),
        videoWidth: 540,
        videoHeight: 1080,
      );

      expect(rect.width, closeTo(200, 0.001));
      expect(rect.height, closeTo(400, 0.001));
      expect(rect.left, closeTo(100, 0.001));
      expect(rect.top, closeTo(0, 0.001));
    });

    test('strips follow the scaled and letterboxed video rectangle', () {
      OverlayFrameData frameAt({
        required double width,
        required double height,
        double offsetX = 0,
        double offsetY = 0,
      }) =>
          OverlayGeometry.computeFrame(
            timestampMs: 0,
            notes: const [_note],
            calibration: _calibration(),
            style: const OverlayStyle(),
            sync: const SyncSettings(),
            displayWidth: width,
            displayHeight: height,
            displayOffsetX: offsetX,
            displayOffsetY: offsetY,
            calibrationWidth: 520,
            calibrationHeight: 480,
          );

      final base = frameAt(width: 520, height: 480);
      final scaled = frameAt(width: 1040, height: 960);
      final shifted = frameAt(width: 520, height: 480, offsetX: 30, offsetY: 70);

      // Doubling the display doubles every coordinate.
      expect(scaled.strips.first.quad[0].dx,
          closeTo(base.strips.first.quad[0].dx * 2, 0.001));
      expect(scaled.strips.first.quad[0].dy,
          closeTo(base.strips.first.quad[0].dy * 2, 0.001));

      // A letterbox offset translates the overlay by exactly that offset.
      expect(shifted.strips.first.quad[0].dx,
          closeTo(base.strips.first.quad[0].dx + 30, 0.001));
      expect(shifted.strips.first.quad[0].dy,
          closeTo(base.strips.first.quad[0].dy + 70, 0.001));
    });

    test('the keyboard edge of the lane lands on the calibrated corners', () {
      final frame = OverlayGeometry.computeFrame(
        timestampMs: 0,
        notes: const [],
        calibration: _calibration(),
        style: const OverlayStyle(),
        sync: const SyncSettings(),
        displayWidth: 260,
        displayHeight: 240,
        displayOffsetX: 20,
        displayOffsetY: 10,
        calibrationWidth: 520,
        calibrationHeight: 480,
      );

      // Corners are (0,400) and (520,400) at 520x480, halved and shifted.
      expect(frame.fallLaneQuad![0].dx, closeTo(20, 0.001));
      expect(frame.fallLaneQuad![0].dy, closeTo(210, 0.001));
      expect(frame.fallLaneQuad![1].dx, closeTo(280, 0.001));
      expect(frame.fallLaneQuad![1].dy, closeTo(210, 0.001));
    });
  });

  test('the native style payload carries every shape field', () {
    final json = const OverlayStyle(
      cornerRadius: 0.3,
      borderWidth: 0.05,
      fallDirection: FallDirection.bottomToTop,
    ).toNativeJson();

    expect(json['corner_radius'], 0.3);
    expect(json['border_width'], 0.05);
    expect(json['fall_direction'], 'BottomToTop');
    expect(json['border_color'], isA<List<double>>());
    expect(json['key_highlight_color'], isA<List<double>>());
  });

  group('key placement', () {
    // The calibration maps one white key to 10 display pixels.
    const whiteKey = 10.0;

    test('a black key sits between its two neighbouring white keys', () {
      // C#4 between C4 and D4, D#4 between D4 and E4, and so on.
      const pairs = {
        61: [60, 62],
        63: [62, 64],
        66: [65, 67],
        68: [67, 69],
        70: [69, 71],
      };

      pairs.forEach((black, neighbours) {
        final centre = _keyCentre(black);
        final left = _keyCentre(neighbours[0]);
        final right = _keyCentre(neighbours[1]);

        expect(centre, greaterThan(left),
            reason: 'black key $black must be right of white ${neighbours[0]}');
        expect(centre, lessThan(right),
            reason: 'black key $black must be left of white ${neighbours[1]}');
      });
    });

    test('a black key never lands on top of a white key', () {
      for (final black in [61, 63, 66, 68, 70]) {
        for (final white in [60, 62, 64, 65, 67, 69, 71]) {
          expect((_keyCentre(black) - _keyCentre(white)).abs(),
              greaterThan(whiteKey * 0.3),
              reason: 'black $black overlaps white $white');
        }
      }
    });

    test('a black key straddles the seam between the white keys', () {
      // The seam between C4 and D4 is halfway between their centres.
      final seam = (_keyCentre(60) + _keyCentre(62)) / 2;
      expect(_keyCentre(61), closeTo(seam, whiteKey * 0.15));
    });

    test('white keys stay evenly spaced one key apart', () {
      const whites = [60, 62, 64, 65, 67, 69, 71, 72];
      for (var i = 1; i < whites.length; i++) {
        expect(_keyCentre(whites[i]) - _keyCentre(whites[i - 1]),
            closeTo(whiteKey, 0.001));
      }
    });
  });
}
