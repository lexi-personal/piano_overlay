import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/models/calibration.dart';
import 'package:piano_overlay/models/midi_note.dart';
import 'package:piano_overlay/models/overlay_style.dart';
import 'package:piano_overlay/features/preview/overlay_painter.dart';
import 'package:piano_overlay/services/project_provider.dart';
import 'package:piano_overlay/shared/overlay_geometry.dart';

/// A flat, head-on keyboard: canonical (x, y) maps to (10x, 80y + 400), so the
/// key top sits at y=400px, the front edge at y=480px, and a white key is 9px
/// wide (0.9 canonical units).
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

/// Middle C, sounding from 1000ms to 1500ms.
const _note = MidiNote(
  pitch: 60,
  velocity: 100,
  startMs: 1000,
  durationMs: 500,
  channel: 0,
  track: 0,
);

OverlayFrameData _frame(
  OverlayStyle style, {
  double timestampMs = 1200,
  List<MidiNote>? notes,
}) =>
    OverlayGeometry.computeFrame(
      timestampMs: timestampMs,
      notes: notes ?? const [_note],
      calibration: _calibration(),
      style: style,
      sync: const SyncSettings(),
      displayWidth: 520,
      displayHeight: 480,
    );

KeyHighlightRenderData _highlight(
  OverlayStyle style, {
  double timestampMs = 1200,
  List<MidiNote>? notes,
}) =>
    _frame(style, timestampMs: timestampMs, notes: notes).keyHighlights.single;

void main() {
  group('key highlight geometry', () {
    test('defaults light the whole key top at the picked opacity', () {
      final highlight = _highlight(const OverlayStyle());

      // Spans the full front-to-back extent of the key.
      expect(highlight.quad[0].dy, closeTo(400, 0.001));
      expect(highlight.quad[3].dy, closeTo(480, 0.001));
      // 0x40 of 0xFF.
      expect(highlight.color.opacity, closeTo(0x40 / 0xFF, 0.005));
      expect(highlight.glowIntensity, 0);
      expect(highlight.cornerRadius, 0);
    });

    test('size shrinks the highlight toward the front edge of the key', () {
      final highlight =
          _highlight(const OverlayStyle(keyHighlightSize: 0.25));

      // The front edge stays put; only the back edge moves forward.
      expect(highlight.quad[3].dy, closeTo(480, 0.001));
      expect(highlight.quad[2].dy, closeTo(480, 0.001));
      expect(highlight.quad[0].dy, closeTo(460, 0.001));
      expect(highlight.quad[1].dy, closeTo(460, 0.001));
    });

    test('size does not change the highlight width', () {
      double width(KeyHighlightRenderData h) => (h.quad[2] - h.quad[3]).distance;

      expect(
        width(_highlight(const OverlayStyle(keyHighlightSize: 0.2))),
        closeTo(width(_highlight(const OverlayStyle())), 0.001),
      );
    });

    test('intensity scales the highlight alpha', () {
      final base = _highlight(const OverlayStyle()).color.opacity;
      final doubled =
          _highlight(const OverlayStyle(keyHighlightIntensity: 2.0))
              .color
              .opacity;

      expect(doubled, closeTo(base * 2, 0.005));
    });

    test('intensity cannot push the alpha past fully opaque', () {
      final highlight =
          _highlight(const OverlayStyle(keyHighlightIntensity: 10.0));

      expect(highlight.color.opacity, closeTo(1.0, 0.001));
    });

    test('intensity of zero hides the highlight', () {
      final highlight =
          _highlight(const OverlayStyle(keyHighlightIntensity: 0.0));

      expect(highlight.color.opacity, closeTo(0.0, 0.001));
    });

    test('no highlight survives the note release without a fade', () {
      // The note ended 250ms ago and the strip has collapsed to nothing.
      final frame = _frame(const OverlayStyle(), timestampMs: 1750);

      expect(frame.keyHighlights, isEmpty);
    });

    test('fade keeps the highlight alive and decays it after release', () {
      const style = OverlayStyle(keyHighlightFadeMs: 500);
      final full = _highlight(style).color.opacity;

      // Halfway through the fade.
      final half = _highlight(style, timestampMs: 1750).color.opacity;
      expect(half, closeTo(full * 0.5, 0.01));

      // Three quarters through.
      final quarter = _highlight(style, timestampMs: 1875).color.opacity;
      expect(quarter, closeTo(full * 0.25, 0.01));
    });

    test('fade ends exactly when the fade duration elapses', () {
      const style = OverlayStyle(keyHighlightFadeMs: 500);

      expect(_frame(style, timestampMs: 1999).keyHighlights, hasLength(1));
      expect(_frame(style, timestampMs: 2001).keyHighlights, isEmpty);
    });

    test('fade outlives the strip trail when it is the longer of the two', () {
      // The strip trail is 200ms, so a 900ms highlight fade would be cut short
      // if the note were culled on the strip's schedule.
      const style = OverlayStyle(keyHighlightFadeMs: 900);

      expect(_frame(style, timestampMs: 2300).keyHighlights, hasLength(1));
    });

    test('glow and rounding are carried onto the highlight', () {
      final highlight = _highlight(const OverlayStyle(
        keyHighlightGlow: 0.6,
        keyHighlightGlowRadius: 12,
        keyHighlightCornerRadius: 0.5,
      ));

      expect(highlight.glowIntensity, closeTo(0.6, 0.001));
      expect(highlight.glowRadius, closeTo(12, 0.001));
      // Half of the 9px white key width.
      expect(highlight.cornerRadius, closeTo(4.5, 0.001));
    });

    test('use note color takes the white key color for a white key', () {
      final highlight = _highlight(const OverlayStyle(
        keyHighlightUseNoteColor: true,
        whiteKeyColor: Color(0xFF00FF00),
      ));

      expect(highlight.color.red, 0);
      expect(highlight.color.green, 255);
      expect(highlight.color.blue, 0);
      // The hue comes from the note, but the strength still comes from the
      // highlight color's own alpha.
      expect(highlight.color.opacity, closeTo(0x40 / 0xFF, 0.005));
    });

    test('use note color takes the black key color for a black key', () {
      final highlight = _highlight(
        const OverlayStyle(
          keyHighlightUseNoteColor: true,
          blackKeyColor: Color(0xFF0000FF),
        ),
        notes: const [
          MidiNote(
            pitch: 61, // C#4
            velocity: 100,
            startMs: 1000,
            durationMs: 500,
            channel: 0,
            track: 0,
          ),
        ],
      );

      expect(highlight.color.blue, 255);
      expect(highlight.color.red, 0);
    });

    test('use note color follows the hand colors when those are on', () {
      final highlight = _highlight(
        const OverlayStyle(
          keyHighlightUseNoteColor: true,
          useHandColors: true,
          rightHandColor: Color(0xFFFF00FF),
        ),
        notes: const [
          MidiNote(
            pitch: 60,
            velocity: 100,
            startMs: 1000,
            durationMs: 500,
            channel: 0,
            track: 1, // right hand
          ),
        ],
      );

      expect(highlight.color.red, 255);
      expect(highlight.color.green, 0);
      expect(highlight.color.blue, 255);
    });

    test('disabling the highlight suppresses it entirely', () {
      final frame = _frame(const OverlayStyle(keyHighlightEnabled: false));

      expect(frame.keyHighlights, isEmpty);
      expect(frame.strips, hasLength(1));
    });

    test('a disabled highlight does not keep dead notes alive', () {
      const style =
          OverlayStyle(keyHighlightEnabled: false, keyHighlightFadeMs: 5000);
      final frame = _frame(style, timestampMs: 3000);

      expect(frame.keyHighlights, isEmpty);
      expect(frame.strips, isEmpty);
    });
  });

  group('key highlight persistence', () {
    test('every highlight setting survives a save and load', () async {
      const style = OverlayStyle(
        keyHighlightEnabled: true,
        keyHighlightColor: Color(0x8012AB34),
        keyHighlightIntensity: 1.75,
        keyHighlightSize: 0.35,
        keyHighlightGlow: 0.6,
        keyHighlightGlowRadius: 21.5,
        keyHighlightFadeMs: 420.0,
        keyHighlightCornerRadius: 0.4,
        keyHighlightUseNoteColor: true,
      );

      final provider = ProjectProvider();
      provider.createProject('Highlight Test');
      provider.updateStyle(style);

      final dir = Directory.systemTemp.createTempSync('pv_highlight');
      final path = await provider.saveProject(dir.path);

      final reloaded = ProjectProvider();
      await reloaded.loadProject(path);
      final loaded = reloaded.project!.style;

      expect(loaded.keyHighlightColor.value, 0x8012AB34);
      expect(loaded.keyHighlightIntensity, 1.75);
      expect(loaded.keyHighlightSize, 0.35);
      expect(loaded.keyHighlightGlow, 0.6);
      expect(loaded.keyHighlightGlowRadius, 21.5);
      expect(loaded.keyHighlightFadeMs, 420.0);
      expect(loaded.keyHighlightCornerRadius, 0.4);
      expect(loaded.keyHighlightUseNoteColor, isTrue);

      dir.deleteSync(recursive: true);
    });

    test('a project saved before these settings existed loads the defaults',
        () async {
      // Round-trip a style, then strip the new keys back out of the saved file
      // to stand in for a project written by an older build.
      final provider = ProjectProvider();
      provider.createProject('Legacy Test');
      provider.updateStyle(const OverlayStyle());

      final dir = Directory.systemTemp.createTempSync('pv_legacy');
      final path = await provider.saveProject(dir.path);

      final file = File(path);
      var contents = file.readAsStringSync();
      for (final key in const [
        'key_highlight_intensity',
        'key_highlight_size',
        'key_highlight_glow',
        'key_highlight_glow_radius',
        'key_highlight_fade_ms',
        'key_highlight_corner_radius',
        'key_highlight_use_note_color',
      ]) {
        expect(contents, contains(key));
        contents = contents.replaceAll(
            RegExp('"$key"\\s*:\\s*(true|false|[-0-9.eE]+),?'), '');
      }
      file.writeAsStringSync(contents);

      final reloaded = ProjectProvider();
      await reloaded.loadProject(path);
      final loaded = reloaded.project!.style;

      const defaults = OverlayStyle();
      expect(loaded.keyHighlightIntensity, defaults.keyHighlightIntensity);
      expect(loaded.keyHighlightSize, defaults.keyHighlightSize);
      expect(loaded.keyHighlightGlow, defaults.keyHighlightGlow);
      expect(loaded.keyHighlightGlowRadius, defaults.keyHighlightGlowRadius);
      expect(loaded.keyHighlightFadeMs, defaults.keyHighlightFadeMs);
      expect(
          loaded.keyHighlightCornerRadius, defaults.keyHighlightCornerRadius);
      expect(loaded.keyHighlightUseNoteColor,
          defaults.keyHighlightUseNoteColor);

      dir.deleteSync(recursive: true);
    });
  });
}
