import 'dart:io';
import 'dart:convert';
import 'package:xml/xml.dart';
import '../../models/midi_note.dart';

class AbletonMidiTrack {
  final String name;
  final int index;
  final int noteCount;
  final List<MidiNote> notes;

  const AbletonMidiTrack({
    required this.name,
    required this.index,
    required this.noteCount,
    required this.notes,
  });
}

/// Where an audio file inside a Live project came from.
///
/// Live's `Samples/Imported` and `Samples/Processed` folders fill up with the
/// individual note recordings that back a sampler instrument (for example
/// `GrandPiano B6 ff.aif`). Those are never the track you want to play the
/// overlay against, so they are kept apart from real recordings and bounces.
enum AbletonAudioKind {
  /// A bounce, render, or audio clip you recorded — the useful kind.
  recording,

  /// One note of a sampler instrument.
  instrumentSample,
}

class AbletonAudioFile {
  final String path;
  final String name;
  final int sizeBytes;
  final AbletonAudioKind kind;

  /// Folder the file sits in, relative to the project, for disambiguation.
  final String relativeDir;

  const AbletonAudioFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.kind = AbletonAudioKind.recording,
    this.relativeDir = '',
  });
}

class AbletonParseResult {
  final String projectName;
  final List<AbletonMidiTrack> midiTracks;
  final List<AbletonAudioFile> audioFiles;
  final double? tempo;
  final int? timeSignatureNumerator;
  final int? timeSignatureDenominator;

  const AbletonParseResult({
    required this.projectName,
    required this.midiTracks,
    required this.audioFiles,
    this.tempo,
    this.timeSignatureNumerator,
    this.timeSignatureDenominator,
  });
}

class AbletonParser {
  const AbletonParser._();

  static const _audioExtensions = [
    '.wav',
    '.mp3',
    '.aiff',
    '.aif',
    '.flac',
    '.ogg',
    '.m4a',
  ];

  /// Parses an Ableton Live Set (.als) file and extracts MIDI notes and metadata.
  static Future<AbletonParseResult> parse(String alsFilePath) async {
    final file = File(alsFilePath);
    final compressedBytes = await file.readAsBytes();
    final xmlBytes = gzip.decode(compressedBytes);
    final xmlString = utf8.decode(xmlBytes);
    final document = XmlDocument.parse(xmlString);

    final projectName = _extractProjectName(alsFilePath);
    final tempo = _extractTempo(document);
    final timeSignature = _extractTimeSignature(document);
    final midiTracks = _extractMidiTracks(document, tempo ?? 120.0);
    final audioFiles = await _scanAudioFiles(alsFilePath);

    return AbletonParseResult(
      projectName: projectName,
      midiTracks: midiTracks,
      audioFiles: audioFiles,
      tempo: tempo,
      timeSignatureNumerator: timeSignature?.$1,
      timeSignatureDenominator: timeSignature?.$2,
    );
  }

  static String _extractProjectName(String alsFilePath) {
    final fileName = alsFilePath.split(Platform.pathSeparator).last;
    if (fileName.toLowerCase().endsWith('.als')) {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  static double? _extractTempo(XmlDocument document) {
    try {
      final liveSet = document.rootElement.getElement('LiveSet');
      if (liveSet == null) return null;

      final masterTrack = liveSet.getElement('MasterTrack');
      if (masterTrack == null) return null;

      // Traverse to find Tempo > Manual
      final tempo = _findElementRecursive(masterTrack, 'Tempo');
      if (tempo == null) return null;

      final manual = tempo.getElement('Manual');
      if (manual == null) return null;

      final value = manual.getAttribute('Value');
      if (value == null) return null;

      return double.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  static (int, int)? _extractTimeSignature(XmlDocument document) {
    try {
      final liveSet = document.rootElement.getElement('LiveSet');
      if (liveSet == null) return null;

      final masterTrack = liveSet.getElement('MasterTrack');
      if (masterTrack == null) return null;

      final timeSignature = _findElementRecursive(masterTrack, 'TimeSignature');
      if (timeSignature == null) return null;

      final timeSignatures =
          timeSignature.getElement('TimeSignatures');
      if (timeSignatures == null) return null;

      final remoteableTimeSignature =
          timeSignatures.getElement('RemoteableTimeSignature');
      if (remoteableTimeSignature == null) return null;

      final numerator = remoteableTimeSignature.getElement('Numerator');
      final denominator = remoteableTimeSignature.getElement('Denominator');

      final numValue = numerator?.getAttribute('Value');
      final denValue = denominator?.getAttribute('Value');

      if (numValue == null || denValue == null) return null;

      final num = int.tryParse(numValue);
      final den = int.tryParse(denValue);

      if (num == null || den == null) return null;
      return (num, den);
    } catch (_) {
      return null;
    }
  }

  static List<AbletonMidiTrack> _extractMidiTracks(
      XmlDocument document, double bpm) {
    final result = <AbletonMidiTrack>[];

    final liveSet = document.rootElement.getElement('LiveSet');
    if (liveSet == null) return result;

    final tracks = liveSet.getElement('Tracks');
    if (tracks == null) return result;

    final midiTrackElements = tracks.childElements
        .where((e) => e.name.local == 'MidiTrack')
        .toList();

    for (var i = 0; i < midiTrackElements.length; i++) {
      final trackElement = midiTrackElements[i];
      final trackName = _extractTrackName(trackElement);
      final notes = _extractNotesFromTrack(trackElement, i, bpm);

      result.add(AbletonMidiTrack(
        name: trackName,
        index: i,
        noteCount: notes.length,
        notes: notes,
      ));
    }

    return result;
  }

  static String _extractTrackName(XmlElement trackElement) {
    final nameElement = trackElement.getElement('Name');
    if (nameElement != null) {
      final effectiveName = nameElement.getElement('EffectiveName');
      if (effectiveName != null) {
        final value = effectiveName.getAttribute('Value');
        if (value != null && value.isNotEmpty) return value;
      }

      final userName = nameElement.getElement('UserName');
      if (userName != null) {
        final value = userName.getAttribute('Value');
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return 'Untitled';
  }

  /// Clips laid out in the Arrangement view.
  static const _arrangementClipPath = [
    'DeviceChain',
    'MainSequencer',
    'ClipTimeable',
    'ArrangerAutomation',
    'Events',
    'MidiClip',
  ];

  /// Clips sitting in Session view slots. Note the doubled `ClipSlot`: the
  /// outer element is the slot, the inner one wraps the clip itself.
  static const _sessionClipPath = [
    'DeviceChain',
    'MainSequencer',
    'ClipSlotList',
    'ClipSlot',
    'ClipSlot',
    'Value',
    'MidiClip',
  ];

  static List<MidiNote> _extractNotesFromTrack(
      XmlElement trackElement, int trackIndex, double bpm) {
    final notes = <MidiNote>[];
    final msPerBeat = 60000.0 / bpm;

    // Clips must be looked up by their exact path. A recursive search for
    // every `MidiClip` under the track also picks up `TakeLanes`, which holds
    // each raw pass of a comped recording. Live never plays those, and on a
    // real comped take they outnumber the arrangement by several times over.
    var clips = _elementsAtPath(trackElement, _arrangementClipPath);
    if (clips.isEmpty) {
      clips = _elementsAtPath(trackElement, _sessionClipPath);
    }

    for (final clip in clips) {
      // A deactivated clip stays in the set but makes no sound.
      if (_getBoolAttribute(clip, 'Disabled') ?? false) continue;
      _collectClipNotes(clip, trackIndex, msPerBeat, notes);
    }

    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
    return notes;
  }

  /// Append every note [clip] actually sounds to [notes].
  ///
  /// Trimming a clip in Live does not delete notes, it only moves the loop
  /// brace: the stored note list still holds everything that was ever played
  /// into the clip. Only notes inside `[LoopStart, LoopEnd)` sound, and a note
  /// running past the brace is cut off there rather than ringing on.
  static void _collectClipNotes(
    XmlElement clip,
    int trackIndex,
    double msPerBeat,
    List<MidiNote> notes,
  ) {
    final clipStart = _getDoubleAttribute(clip, 'CurrentStart') ?? 0.0;
    final clipEnd = _getDoubleAttribute(clip, 'CurrentEnd') ?? 0.0;

    final loop = clip.getElement('Loop');
    final loopStart =
        loop == null ? 0.0 : _getDoubleAttribute(loop, 'LoopStart') ?? 0.0;
    final loopEnd =
        loop == null ? 0.0 : _getDoubleAttribute(loop, 'LoopEnd') ?? 0.0;
    final loopOn = loop != null && (_getBoolAttribute(loop, 'LoopOn') ?? false);

    final loopLength = loopEnd - loopStart;
    if (loopLength <= 0) return;

    // How far the clip runs along the arrangement. A Session clip has no
    // arrangement extent, so it plays its brace once.
    var playLength = clipEnd - clipStart;
    if (playLength <= 0) playLength = loopLength;

    // A looping clip repeats the brace until the clip block is full; an
    // unlooped one plays it at most once.
    final passes = loopOn ? (playLength / loopLength).ceil() : 1;
    if (!loopOn && playLength > loopLength) playLength = loopLength;

    final keyTracks = clip.getElement('Notes')?.getElement('KeyTracks');
    if (keyTracks == null) return;

    for (final keyTrack
        in keyTracks.childElements.where((e) => e.name.local == 'KeyTrack')) {
      final pitch = int.tryParse(
          keyTrack.getElement('MidiKey')?.getAttribute('Value') ?? '');
      if (pitch == null) continue;

      final events = keyTrack.getElement('Notes');
      if (events == null) continue;

      for (final event in events.childElements
          .where((e) => e.name.local == 'MidiNoteEvent')) {
        // Notes can be deactivated one by one without being deleted.
        if (event.getAttribute('IsEnabled') == 'false') continue;

        final time = double.tryParse(event.getAttribute('Time') ?? '');
        if (time == null || time < loopStart || time >= loopEnd) continue;

        final velocity =
            double.tryParse(event.getAttribute('Velocity') ?? '')?.round() ??
                100;
        final duration =
            (double.tryParse(event.getAttribute('Duration') ?? '') ?? 0.0)
                .clamp(0.0, loopEnd - time);

        for (var pass = 0; pass < passes; pass++) {
          final offset = (time - loopStart) + pass * loopLength;
          if (offset >= playLength) break;

          final audible = duration.clamp(0.0, playLength - offset);
          if (audible <= 0) continue;

          notes.add(MidiNote(
            pitch: pitch,
            velocity: velocity,
            startMs: (clipStart + offset) * msPerBeat,
            durationMs: audible * msPerBeat,
            channel: 0,
            track: trackIndex,
          ));
        }
      }
    }
  }

  static Future<List<AbletonAudioFile>> _scanAudioFiles(
      String alsFilePath) async {
    final alsFile = File(alsFilePath);
    final projectDir = alsFile.parent;
    final seen = <String>{};
    final audioFiles = <AbletonAudioFile>[];

    final dirsToScan = [
      projectDir,
      Directory('${projectDir.path}${Platform.pathSeparator}Samples'),
      Directory('${projectDir.path}${Platform.pathSeparator}Bounces'),
      Directory('${projectDir.path}${Platform.pathSeparator}Renders'),
    ];

    for (final dir in dirsToScan) {
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;

        final ext = _fileExtension(entity.path);
        if (!_audioExtensions.contains(ext)) continue;

        final canonicalPath = entity.path;
        if (seen.contains(canonicalPath)) continue;
        seen.add(canonicalPath);

        final stat = await entity.stat();
        audioFiles.add(AbletonAudioFile(
          path: canonicalPath,
          name: canonicalPath.split(Platform.pathSeparator).last,
          sizeBytes: stat.size,
          kind: _classify(projectDir.path, canonicalPath),
          relativeDir: _relativeDir(projectDir.path, canonicalPath),
        ));
      }
    }

    // Recordings first, then largest first: a bounce of the whole take is
    // always bigger than a single sampled note.
    audioFiles.sort((a, b) {
      if (a.kind != b.kind) {
        return a.kind == AbletonAudioKind.recording ? -1 : 1;
      }
      return b.sizeBytes.compareTo(a.sizeBytes);
    });
    return audioFiles;
  }

  /// Folder holding [filePath], relative to [projectDirPath].
  static String _relativeDir(String projectDirPath, String filePath) {
    final sep = Platform.pathSeparator;
    final dir = filePath.substring(0, filePath.lastIndexOf(sep));
    if (dir == projectDirPath) return '';
    if (!dir.startsWith('$projectDirPath$sep')) return dir;
    return dir.substring(projectDirPath.length + 1);
  }

  static AbletonAudioKind _classify(String projectDirPath, String filePath) {
    final rel = _relativeDir(projectDirPath, filePath)
        .replaceAll('\\', '/')
        .toLowerCase();
    if (rel.startsWith('samples/imported') ||
        rel.startsWith('samples/processed')) {
      return AbletonAudioKind.instrumentSample;
    }
    return AbletonAudioKind.recording;
  }

  static String _fileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }

  static double? _getDoubleAttribute(XmlElement parent, String childName) {
    final child = parent.getElement(childName);
    if (child == null) return null;
    final value = child.getAttribute('Value');
    if (value == null) return null;
    return double.tryParse(value);
  }

  static bool? _getBoolAttribute(XmlElement parent, String childName) {
    final value = parent.getElement(childName)?.getAttribute('Value');
    if (value == null) return null;
    return value == 'true';
  }

  static XmlElement? _findElementRecursive(XmlElement parent, String name) {
    final direct = parent.getElement(name);
    if (direct != null) return direct;

    for (final child in parent.childElements) {
      final found = _findElementRecursive(child, name);
      if (found != null) return found;
    }
    return null;
  }

  /// Every element reached by walking [path] down from [root], one named step
  /// at a time.
  ///
  /// Unlike a recursive search this cannot stray into a sibling branch that
  /// happens to reuse an element name, which is what keeps take lanes out of
  /// the clip list.
  static List<XmlElement> _elementsAtPath(
      XmlElement root, List<String> path) {
    var current = <XmlElement>[root];
    for (final name in path) {
      final next = <XmlElement>[];
      for (final element in current) {
        next.addAll(element.childElements.where((e) => e.name.local == name));
      }
      if (next.isEmpty) return const [];
      current = next;
    }
    return current;
  }
}
