import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/ableton/ableton_parser.dart';

/// Minimal but valid Live set: one MIDI track so parsing succeeds.
const _als = '''
<?xml version="1.0" encoding="UTF-8"?>
<Ableton MajorVersion="5" MinorVersion="11.0_11300">
  <LiveSet>
    <Tracks>
      <MidiTrack Id="8">
        <Name><EffectiveName Value="Piano" /></Name>
      </MidiTrack>
    </Tracks>
  </LiveSet>
</Ableton>
''';

/// Two tracks sharing a name, with different clip counts — the situation that
/// makes the import dialog ambiguous without a track number.
const _duplicateNames = '''
<?xml version="1.0" encoding="UTF-8"?>
<Ableton MajorVersion="5" MinorVersion="11.0_11300">
  <LiveSet>
    <Tracks>
      <MidiTrack Id="8">
        <Name><EffectiveName Value="Winter - Piano" /></Name>
        <ClipSlotList>
          <MidiClip Id="0"><Name Value="a" /></MidiClip>
          <MidiClip Id="1"><Name Value="a" /></MidiClip>
        </ClipSlotList>
      </MidiTrack>
      <MidiTrack Id="9">
        <Name><EffectiveName Value="Winter - Piano" /></Name>
        <ClipSlotList>
          <MidiClip Id="2"><Name Value="a" /></MidiClip>
        </ClipSlotList>
      </MidiTrack>
    </Tracks>
  </LiveSet>
</Ableton>
''';

void main() {
  late Directory project;

  setUp(() async {
    project = await Directory.systemTemp.createTemp('als_scan');
    // Live stores .als files gzipped.
    await File('${project.path}/Project.als')
        .writeAsBytes(gzip.encode(utf8.encode(_als)));
  });

  tearDown(() => project.delete(recursive: true));

  Future<void> write(String relative, int bytes) async {
    final file = File('${project.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 0));
  }

  Future<List<AbletonAudioFile>> scan() async {
    final result = await AbletonParser.parse('${project.path}/Project.als');
    return result.audioFiles;
  }

  test('sampler instrument samples are separated from real recordings',
      () async {
    await write('Samples/Imported/GrandPiano B6 ff.aif', 500);
    await write('Samples/Imported/GrandPiano F6 mf.aif', 500);
    await write('Samples/Processed/Consolidate/take.wav', 400);
    await write('Bounces/full take.wav', 9000);

    final files = await scan();
    final kinds = {for (final f in files) f.name: f.kind};

    expect(kinds['GrandPiano B6 ff.aif'], AbletonAudioKind.instrumentSample);
    expect(kinds['GrandPiano F6 mf.aif'], AbletonAudioKind.instrumentSample);
    expect(kinds['take.wav'], AbletonAudioKind.instrumentSample);
    expect(kinds['full take.wav'], AbletonAudioKind.recording);
  });

  test('recordings sort ahead of samples even when smaller', () async {
    await write('Samples/Imported/huge sample.aif', 9000);
    await write('Bounces/tiny bounce.wav', 100);

    final files = await scan();
    expect(files.first.name, 'tiny bounce.wav');
    expect(files.last.name, 'huge sample.aif');
  });

  test('audio recorded into the set counts as a recording', () async {
    await write('Samples/Recorded/1-Audio.wav', 2000);

    final files = await scan();
    expect(files.single.kind, AbletonAudioKind.recording);
    expect(files.single.relativeDir, 'Samples/Recorded');
  });

  test('files next to the .als have no relative folder', () async {
    await write('render.wav', 2000);

    final files = await scan();
    expect(files.single.relativeDir, isEmpty);
    expect(files.single.kind, AbletonAudioKind.recording);
  });

  test('tracks sharing a name keep distinct positions and clip counts',
      () async {
    await File('${project.path}/Dupes.als')
        .writeAsBytes(gzip.encode(utf8.encode(_duplicateNames)));

    final r = await AbletonParser.parse('${project.path}/Dupes.als');

    expect(r.midiTracks.map((t) => t.name), ['Winter - Piano', 'Winter - Piano']);
    expect(r.midiTracks.map((t) => t.index), [0, 1]);
    expect(r.midiTracks.map((t) => t.clipCount), [2, 1]);
  });
}
