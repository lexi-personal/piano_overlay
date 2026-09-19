import 'package:flutter/material.dart';

import '../../models/midi_note.dart';
import '../../models/track_settings.dart';

/// Multi-track timeline showing the video clip alongside one lane per MIDI
/// track, with a playhead, click-to-seek and drag-to-nudge.
class TimelinePanel extends StatelessWidget {
  static const double laneHeight = 34;
  static const double gutterWidth = 170;

  final Duration duration;
  final Duration position;
  final String? videoName;
  final List<MidiTrack> tracks;
  final TrackSettings Function(int index) settingsFor;
  final void Function(int index, TrackSettings settings) onTrackChanged;
  final ValueChanged<Duration> onSeek;

  const TimelinePanel({
    super.key,
    required this.duration,
    required this.position,
    required this.videoName,
    required this.tracks,
    required this.settingsFor,
    required this.onTrackChanged,
    required this.onSeek,
  });

  double get _totalMs {
    final videoMs = duration.inMilliseconds.toDouble();
    var end = videoMs;
    for (var i = 0; i < tracks.length; i++) {
      final offset = settingsFor(i).offsetMs;
      for (final note in tracks[i].notes) {
        final noteEnd = note.startMs + note.durationMs + offset;
        if (noteEnd > end) end = noteEnd;
      }
    }
    return end > 0 ? end : 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = _totalMs;

    return Container(
      color: theme.colorScheme.surface,
      height: laneHeight * (tracks.length + 1) + 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _videoHeader(theme),
                for (var i = 0; i < tracks.length; i++) _trackHeader(theme, i),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pxPerMs = constraints.maxWidth / totalMs;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => onSeek(Duration(
                      milliseconds:
                          (details.localPosition.dx / pxPerMs).round())),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _videoClip(theme, totalMs),
                          for (var i = 0; i < tracks.length; i++)
                            _noteLane(theme, i, totalMs, pxPerMs),
                        ],
                      ),
                      Positioned(
                        left: position.inMilliseconds * pxPerMs,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoHeader(ThemeData theme) {
    return SizedBox(
      height: laneHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.videocam, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                videoName ?? 'No video',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackHeader(ThemeData theme, int index) {
    final settings = settingsFor(index);
    final name = tracks[index].name.isEmpty
        ? 'Track ${index + 1}'
        : tracks[index].name;

    return SizedBox(
      height: laneHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              iconSize: 16,
              tooltip: settings.visible ? 'Hide track' : 'Show track',
              icon: Icon(
                  settings.visible ? Icons.visibility : Icons.visibility_off),
              onPressed: () => onTrackChanged(
                  index, settings.copyWith(visible: !settings.visible)),
            ),
            Expanded(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: settings.visible ? null : theme.disabledColor,
                  )),
            ),
            Tooltip(
              message: 'Which hand plays this track',
              child: DropdownButton<Hand>(
                value: settings.hand,
                isDense: true,
                underline: const SizedBox.shrink(),
                onChanged: (hand) => hand == null
                    ? null
                    : onTrackChanged(index, settings.copyWith(hand: hand)),
                items: const [
                  DropdownMenuItem(
                      value: Hand.left,
                      child: Text('L', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(
                      value: Hand.right,
                      child: Text('R', style: TextStyle(fontSize: 12))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoClip(ThemeData theme, double totalMs) {
    final fraction =
        totalMs > 0 ? (duration.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      height: laneHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction == 0 ? 0.0001 : fraction,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colorScheme.primary, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteLane(ThemeData theme, int index, double totalMs, double pxPerMs) {
    final settings = settingsFor(index);

    return SizedBox(
      height: laneHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Dragging a lane nudges it against the video, which is how the user
        // lines up a MIDI recording with the performance.
        onHorizontalDragUpdate: (details) {
          if (pxPerMs <= 0) return;
          onTrackChanged(
            index,
            settings.copyWith(offsetMs: settings.offsetMs + details.delta.dx / pxPerMs),
          );
        },
        child: Tooltip(
          message: 'Drag to nudge (${settings.offsetMs.round()} ms)',
          waitDuration: const Duration(milliseconds: 600),
          child: CustomPaint(
            painter: _NoteLanePainter(
              notes: tracks[index].notes,
              settings: settings,
              totalMs: totalMs,
              color: settings.hand == Hand.left
                  ? const Color(0xFF4FC3F7)
                  : const Color(0xFFFF7043),
              dimmed: !settings.visible,
              gridColor: theme.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteLanePainter extends CustomPainter {
  final List<MidiNote> notes;
  final TrackSettings settings;
  final double totalMs;
  final Color color;
  final bool dimmed;
  final Color gridColor;

  _NoteLanePainter({
    required this.notes,
    required this.settings,
    required this.totalMs,
    required this.color,
    required this.dimmed,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), Paint()..color = gridColor);

    if (notes.isEmpty || totalMs <= 0) return;

    final pxPerMs = size.width / totalMs;
    final paint = Paint()..color = color.withOpacity(dimmed ? 0.2 : 0.85);

    // Spread pitches over the lane height so the shape of the part is
    // recognisable at a glance.
    var lowest = notes.first.pitch;
    var highest = notes.first.pitch;
    for (final note in notes) {
      if (note.pitch < lowest) lowest = note.pitch;
      if (note.pitch > highest) highest = note.pitch;
    }
    final span = (highest - lowest).clamp(1, 127);
    const padding = 4.0;
    final usable = size.height - padding * 2 - 3;

    for (final note in notes) {
      final start = note.startMs + settings.offsetMs;
      if (start < settings.trimStartMs) continue;
      if (settings.trimEndMs != null && start >= settings.trimEndMs!) continue;

      final left = start * pxPerMs;
      final width = (note.durationMs * pxPerMs).clamp(1.0, size.width);
      if (left > size.width) continue;

      final y = padding + usable * (1 - (note.pitch - lowest) / span);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y, width, 3),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_NoteLanePainter old) =>
      old.notes != notes ||
      old.settings != settings ||
      old.totalMs != totalMs ||
      old.color != color ||
      old.dimmed != dimmed;
}
