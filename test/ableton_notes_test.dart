import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/models/midi_note.dart';
import 'package:piano_overlay/services/ableton/ableton_parser.dart';

/// One `MidiNoteEvent`.
String _event(double time, double duration, {bool enabled = true}) =>
    '<MidiNoteEvent Time="$time" Duration="$duration" Velocity="100" '
    'OffVelocity="64" Probability="1" '
    'IsEnabled="${enabled ? 'true' : 'false'}" NoteId="1" />';

/// A `MidiClip` holding one pitch's worth of events.
String _clip({
  required double start,
  required double end,
  required double loopStart,
  required double loopEnd,
  required List<String> events,
  bool loopOn = false,
  bool disabled = false,
  int pitch = 60,
}) =>
    '''
<MidiClip Id="0" Time="$start">
  <CurrentStart Value="$start" />
  <CurrentEnd Value="$end" />
  <Loop>
    <LoopStart Value="$loopStart" />
    <LoopEnd Value="$loopEnd" />
    <StartRelative Value="0" />
    <LoopOn Value="${loopOn ? 'true' : 'false'}" />
    <HiddenLoopStart Value="0" />
    <HiddenLoopEnd Value="4" />
  </Loop>
  <Disabled Value="${disabled ? 'true' : 'false'}" />
  <Notes>
    <KeyTracks>
      <KeyTrack Id="0">
        <Notes>
          ${events.join('\n          ')}
        </Notes>
        <MidiKey Value="$pitch" />
      </KeyTrack>
    </KeyTracks>
  </Notes>
</MidiClip>
''';

/// A Live set with one MIDI track at 120 BPM, so one beat is 500 ms.
String _set({
  String arrangementClips = '',
  String sessionClips = '',
  String takeLaneClips = '',
}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<Ableton MajorVersion="5" MinorVersion="11.0_11300">
  <LiveSet>
    <Tracks>
      <MidiTrack Id="8">
        <Name><EffectiveName Value="Piano" /></Name>
        <TakeLanes>
          <TakeLanes>
            <TakeLane Id="0">
              <ClipAutomation>
                <Events>
                  $takeLaneClips
                </Events>
              </ClipAutomation>
            </TakeLane>
          </TakeLanes>
        </TakeLanes>
        <DeviceChain>
          <MainSequencer>
            <ClipTimeable>
              <ArrangerAutomation>
                <Events>
                  $arrangementClips
                </Events>
              </ArrangerAutomation>
            </ClipTimeable>
            <ClipSlotList>
              <ClipSlot Id="0">
                <ClipSlot>
                  <Value>
                    $sessionClips
                  </Value>
                </ClipSlot>
              </ClipSlot>
            </ClipSlotList>
          </MainSequencer>
        </DeviceChain>
      </MidiTrack>
    </Tracks>
    <MasterTrack>
      <DeviceChain>
        <Mixer>
          <Tempo><Manual Value="120" /></Tempo>
        </Mixer>
      </DeviceChain>
    </MasterTrack>
  </LiveSet>
</Ableton>
''';

void main() {
  late Directory project;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('als_notes');
  });

  tearDown(() => project.delete(recursive: true));

  Future<List<MidiNote>> notesOf(String als) async {
    final path = '${project.path}/Set.als';
    await File(path).writeAsBytes(gzip.encode(utf8.encode(als)));
    final result = await AbletonParser.parse(path);
    return result.midiTracks.single.notes;
  }

  test('the tempo turns beats into milliseconds', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        events: [_event(2, 1)],
      ),
    ));

    // 120 BPM, so one beat is 500 ms.
    expect(notes.single.startMs, closeTo(1000, 0.001));
    expect(notes.single.durationMs, closeTo(500, 0.001));
  });

  test('take lane recordings are not imported', () async {
    // Comping a take leaves every raw pass in TakeLanes. Live plays only the
    // arrangement clip, so importing the lanes multiplies the note count.
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        events: [_event(0, 1)],
      ),
      takeLaneClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        pitch: 72,
        events: [_event(1, 1), _event(2, 1), _event(3, 1)],
      ),
    ));

    expect(notes.map((n) => n.pitch), [60]);
  });

  test('notes trimmed outside the loop brace stay silent', () async {
    // The brace keeps beats 4-8. Everything else was played into the clip but
    // is no longer audible.
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 100,
        end: 104,
        loopStart: 4,
        loopEnd: 8,
        events: [
          _event(0, 1), // before the brace
          _event(3.9, 1), // still before
          _event(4, 1), // first audible
          _event(7, 1), // last audible
          _event(8, 1), // on the brace end, excluded
          _event(12, 1), // past it
        ],
      ),
    ));

    // Local beat 4 maps to the clip's arrangement start of beat 100.
    expect(notes.map((n) => n.startMs / 500), [100, 103]);
  });

  test('a note running past the brace is cut off there', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 8,
        loopStart: 0,
        loopEnd: 8,
        events: [_event(6, 12)],
      ),
    ));

    // Six beats in, with only two left before the brace ends.
    expect(notes.single.durationMs, closeTo(2 * 500, 0.001));
  });

  test('a deactivated note is skipped', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        events: [_event(0, 1), _event(1, 1, enabled: false), _event(2, 1)],
      ),
    ));

    expect(notes.map((n) => n.startMs / 500), [0, 2]);
  });

  test('a deactivated clip makes no sound', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        disabled: true,
        events: [_event(0, 1), _event(1, 1)],
      ),
    ));

    expect(notes, isEmpty);
  });

  test('a looping clip repeats its brace across the clip block', () async {
    // A two-beat brace stretched over eight beats plays four times.
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 8,
        loopStart: 0,
        loopEnd: 2,
        loopOn: true,
        events: [_event(0, 1)],
      ),
    ));

    expect(notes.map((n) => n.startMs / 500), [0, 2, 4, 6]);
  });

  test('a looping clip is cut off mid repetition at the clip end', () async {
    // Seven beats of an eight-beat block leaves the fourth pass unfinished.
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 7,
        loopStart: 0,
        loopEnd: 2,
        loopOn: true,
        events: [_event(1, 2)],
      ),
    ));

    expect(notes.map((n) => n.startMs / 500), [1, 3, 5]);
    // The brace already cuts the two-beat note down to one beat.
    expect(notes.first.durationMs, closeTo(500, 0.001));
  });

  test('an unlooped clip plays its brace only once', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 16,
        loopStart: 0,
        loopEnd: 2,
        events: [_event(0, 1)],
      ),
    ));

    expect(notes, hasLength(1));
  });

  test('session clips are used when the arrangement is empty', () async {
    final notes = await notesOf(_set(
      sessionClips: _clip(
        start: 0,
        end: 0,
        loopStart: 0,
        loopEnd: 4,
        pitch: 64,
        events: [_event(1, 1)],
      ),
    ));

    expect(notes.single.pitch, 64);
    expect(notes.single.startMs, closeTo(500, 0.001));
  });

  test('the arrangement wins when a set has clips in both views', () async {
    final notes = await notesOf(_set(
      arrangementClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        pitch: 60,
        events: [_event(0, 1)],
      ),
      sessionClips: _clip(
        start: 0,
        end: 4,
        loopStart: 0,
        loopEnd: 4,
        pitch: 67,
        events: [_event(0, 1)],
      ),
    ));

    expect(notes.map((n) => n.pitch), [60]);
  });
}
