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

  static List<MidiNote> _extractNotesFromTrack(
      XmlElement trackElement, int trackIndex, double bpm) {
    final notes = <MidiNote>[];
    final msPerBeat = 60000.0 / bpm;

    final midiClips = _findAllElementsRecursive(trackElement, 'MidiClip');

    for (final clip in midiClips) {
      final clipStartBeats = _getDoubleAttribute(clip, 'CurrentStart') ?? 0.0;
      final loopElement = clip.getElement('Loop');
      final loopStartBeats = loopElement != null
          ? _getDoubleAttribute(loopElement, 'LoopStart') ?? 0.0
          : 0.0;

      // Ableton 11+ format: Notes > KeyTracks > KeyTrack
      final notesElement = _findElementRecursive(clip, 'Notes');
      if (notesElement == null) continue;

      final keyTracks = notesElement.getElement('KeyTracks');
      if (keyTracks == null) continue;

      final keyTrackElements = keyTracks.childElements
          .where((e) => e.name.local == 'KeyTrack')
          .toList();

      for (final keyTrack in keyTrackElements) {
        final midiKeyElement = keyTrack.getElement('MidiKey');
        if (midiKeyElement == null) continue;

        final pitch =
            int.tryParse(midiKeyElement.getAttribute('Value') ?? '') ?? 0;

        final keyTrackNotes = keyTrack.getElement('Notes');
        if (keyTrackNotes == null) continue;

        final noteEvents = keyTrackNotes.childElements
            .where((e) => e.name.local == 'MidiNoteEvent')
            .toList();

        for (final event in noteEvents) {
          final time =
              double.tryParse(event.getAttribute('Time') ?? '') ?? 0.0;
          final duration =
              double.tryParse(event.getAttribute('Duration') ?? '') ?? 0.0;
          final velocity =
              int.tryParse(event.getAttribute('Velocity') ?? '') ?? 100;

          final absoluteBeats =
              clipStartBeats + (time - loopStartBeats);
          final startMs = absoluteBeats * msPerBeat;
          final durationMs = duration * msPerBeat;

          notes.add(MidiNote(
            pitch: pitch,
            velocity: velocity,
            startMs: startMs,
            durationMs: durationMs,
            channel: 0,
            track: trackIndex,
          ));
        }
      }
    }

    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
    return notes;
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

  static XmlElement? _findElementRecursive(XmlElement parent, String name) {
    final direct = parent.getElement(name);
    if (direct != null) return direct;

    for (final child in parent.childElements) {
      final found = _findElementRecursive(child, name);
      if (found != null) return found;
    }
    return null;
  }

  static List<XmlElement> _findAllElementsRecursive(
      XmlElement parent, String name) {
    final results = <XmlElement>[];
    _collectElements(parent, name, results);
    return results;
  }

  static void _collectElements(
      XmlElement element, String name, List<XmlElement> results) {
    if (element.name.local == name) {
      results.add(element);
      return;
    }
    for (final child in element.childElements) {
      _collectElements(child, name, results);
    }
  }
}
