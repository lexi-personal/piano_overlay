import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/models/midi_note.dart';
import 'package:piano_overlay/models/project.dart';
import 'package:piano_overlay/models/track_settings.dart';

MidiNote _note(int pitch, double startMs) => MidiNote(
      pitch: pitch,
      velocity: 100,
      startMs: startMs,
      durationMs: 250,
      channel: 0,
      track: 0,
    );

MidiFileData _midi() => MidiFileData(
      tracks: [
        MidiTrack(name: 'Left', notes: [_note(48, 0), _note(50, 1000)], channel: 0),
        MidiTrack(name: 'Right', notes: [_note(72, 500)], channel: 1),
      ],
      durationMs: 2000,
      noteCount: 3,
      initialTempoBpm: 120,
      ticksPerBeat: 480,
      trackCount: 2,
    );

Project _project() => Project.create('Test')..midi = _midi();

void main() {
  group('track defaults', () {
    test('the first track is the left hand, the rest are the right', () {
      expect(TrackSettings.forTrack(0).hand, Hand.left);
      expect(TrackSettings.forTrack(1).hand, Hand.right);
      expect(TrackSettings.forTrack(2).hand, Hand.right);
    });

    test('a project with no saved track state still renders every note', () {
      expect(_project().renderableNotes.length, 3);
    });
  });

  group('track edits', () {
    test('hiding a track removes its notes from the overlay', () {
      final project = _project();
      project.trackSettings[0] = const TrackSettings(visible: false);

      final notes = project.renderableNotes;
      expect(notes.length, 1);
      expect(notes.single.pitch, 72);
    });

    test('the hand assignment drives the note colour group', () {
      final project = _project();
      project.trackSettings[0] = const TrackSettings(hand: Hand.right);
      project.trackSettings[1] = const TrackSettings(hand: Hand.left);

      final byPitch = {
        for (final note in project.renderableNotes) note.pitch: note.track
      };
      expect(byPitch[48], 1);
      expect(byPitch[72], 0);
    });

    test('nudging a track shifts only that track', () {
      final project = _project();
      project.trackSettings[0] = const TrackSettings(offsetMs: 120);

      final notes = project.renderableNotes;
      expect(notes.firstWhere((n) => n.pitch == 48).startMs, 120);
      expect(notes.firstWhere((n) => n.pitch == 72).startMs, 500);
    });

    test('trimming drops notes outside the window', () {
      final project = _project();
      project.trackSettings[0] =
          const TrackSettings(trimStartMs: 600, trimEndMs: 1500);

      final pitches = project.renderableNotes.map((n) => n.pitch).toSet();
      expect(pitches, {50, 72});
    });

    test('trim is measured after the nudge', () {
      final project = _project();
      project.trackSettings[0] =
          const TrackSettings(offsetMs: 700, trimStartMs: 600);
      project.trackSettings[1] = const TrackSettings(visible: false);

      // Both notes move past the trim point, so neither is dropped.
      expect(project.renderableNotes.length, 2);
    });

    test('notes come back sorted by time across tracks', () {
      final starts = _project().renderableNotes.map((n) => n.startMs).toList();
      expect(starts, [0.0, 500.0, 1000.0]);
    });
  });

  group('persistence', () {
    test('settings survive a round trip through JSON', () {
      const original = TrackSettings(
        visible: false,
        hand: Hand.left,
        offsetMs: -42.5,
        trimStartMs: 10,
        trimEndMs: 900,
      );

      final restored = TrackSettings.fromJson(original.toJson());

      expect(restored.visible, isFalse);
      expect(restored.hand, Hand.left);
      expect(restored.offsetMs, -42.5);
      expect(restored.trimStartMs, 10);
      expect(restored.trimEndMs, 900);
    });

    test('an absent trim end stays absent', () {
      final restored =
          TrackSettings.fromJson(const TrackSettings().toJson());
      expect(restored.trimEndMs, isNull);
    });

    test('copyWith can clear the trim end', () {
      const settings = TrackSettings(trimEndMs: 500);
      expect(settings.copyWith(clearTrimEnd: true).trimEndMs, isNull);
      expect(settings.copyWith(offsetMs: 1).trimEndMs, 500);
    });
  });
}
