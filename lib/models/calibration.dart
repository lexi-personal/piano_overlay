import 'dart:ui';

/// A 2D point (mirrors Rust Point2D).
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  factory Point2D.fromJson(Map<String, dynamic> json) {
    return Point2D(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  Offset toOffset() => Offset(x, y);
}

/// Supported keyboard sizes.
enum KeyboardSize {
  keys88(88, 52, 21),
  keys76(76, 45, 28),
  keys61(61, 36, 36),
  keys49(49, 29, 36),
  custom(0, 0, 0);

  final int totalKeys;
  final int whiteKeys;
  final int lowestNote;

  const KeyboardSize(this.totalKeys, this.whiteKeys, this.lowestNote);

  int get highestNote => lowestNote + totalKeys - 1;

  String get label => this == custom ? 'Custom' : '$totalKeys keys';
}

/// Custom key range for when only part of the keyboard is visible.
class KeyRange {
  final int lowestNote;
  final int highestNote;

  const KeyRange({required this.lowestNote, required this.highestNote});

  factory KeyRange.fromPreset(KeyboardSize size) {
    return KeyRange(lowestNote: size.lowestNote, highestNote: size.highestNote);
  }

  int get totalKeys => highestNote - lowestNote + 1;

  int get whiteKeys {
    int count = 0;
    for (int n = lowestNote; n <= highestNote; n++) {
      if (!const [1, 3, 6, 8, 10].contains(n % 12)) count++;
    }
    return count;
  }

  static String noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[midi % 12]}${(midi ~/ 12) - 1}';
  }

  Map<String, dynamic> toJson() => {
    'lowest_note': lowestNote,
    'highest_note': highestNote,
  };

  factory KeyRange.fromJson(Map<String, dynamic> json) {
    return KeyRange(
      lowestNote: json['lowest_note'] as int,
      highestNote: json['highest_note'] as int,
    );
  }
}

/// The 4 corners of the keyboard in video frame coordinates.
class KeyboardCorners {
  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;

  const KeyboardCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  factory KeyboardCorners.fromJson(Map<String, dynamic> json) {
    return KeyboardCorners(
      topLeft: Point2D.fromJson(json['top_left']),
      topRight: Point2D.fromJson(json['top_right']),
      bottomRight: Point2D.fromJson(json['bottom_right']),
      bottomLeft: Point2D.fromJson(json['bottom_left']),
    );
  }

  Map<String, dynamic> toJson() => {
        'top_left': topLeft.toJson(),
        'top_right': topRight.toJson(),
        'bottom_right': bottomRight.toJson(),
        'bottom_left': bottomLeft.toJson(),
      };
}

/// Full calibration data.
class CalibrationData {
  final KeyboardCorners corners;
  final KeyboardSize keyboardSize;
  final KeyRange keyRange;
  final List<List<double>> homography; // 3x3 matrix
  final List<KeyPosition> keyPositions;
  final double calibrationWidth;
  final double calibrationHeight;

  const CalibrationData({
    required this.corners,
    required this.keyboardSize,
    KeyRange? keyRange,
    required this.homography,
    required this.keyPositions,
    this.calibrationWidth = 0,
    this.calibrationHeight = 0,
  }) : keyRange = keyRange ?? const KeyRange(lowestNote: 21, highestNote: 108);

  factory CalibrationData.fromJson(Map<String, dynamic> json) {
    final kbSize = _parseKeyboardSize(json['keyboard_size']);
    return CalibrationData(
      corners: KeyboardCorners.fromJson(json['corners']),
      keyboardSize: kbSize,
      keyRange: json['key_range'] != null
          ? KeyRange.fromJson(json['key_range'])
          : KeyRange.fromPreset(kbSize),
      homography: (json['homography'] as List)
          .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
      keyPositions: (json['key_positions'] as List)
          .map((k) => KeyPosition.fromJson(k))
          .toList(),
      calibrationWidth: (json['calibration_width'] as num?)?.toDouble() ?? 0,
      calibrationHeight: (json['calibration_height'] as num?)?.toDouble() ?? 0,
    );
  }

  static KeyboardSize _parseKeyboardSize(dynamic value) {
    if (value is String) {
      switch (value) {
        case 'Keys88': return KeyboardSize.keys88;
        case 'Keys76': return KeyboardSize.keys76;
        case 'Keys61': return KeyboardSize.keys61;
        case 'Keys49': return KeyboardSize.keys49;
        case 'Custom': return KeyboardSize.custom;
      }
    }
    return KeyboardSize.keys88;
  }
}

/// Position of a single key in screen space.
class KeyPosition {
  final int note;
  final bool isBlack;
  final List<Point2D> screenQuad; // 4 points: TL, TR, BR, BL
  final double canonicalXCenter;

  const KeyPosition({
    required this.note,
    required this.isBlack,
    required this.screenQuad,
    required this.canonicalXCenter,
  });

  factory KeyPosition.fromJson(Map<String, dynamic> json) {
    return KeyPosition(
      note: json['note'] as int,
      isBlack: json['is_black'] as bool,
      screenQuad: (json['screen_quad'] as List)
          .map((p) => Point2D.fromJson(p))
          .toList(),
      canonicalXCenter: (json['canonical_x_center'] as num).toDouble(),
    );
  }
}
