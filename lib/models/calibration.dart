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
  keys49(49, 29, 36);

  final int totalKeys;
  final int whiteKeys;
  final int lowestNote;

  const KeyboardSize(this.totalKeys, this.whiteKeys, this.lowestNote);

  int get highestNote => lowestNote + totalKeys - 1;

  String get label => '$totalKeys keys';
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
  final List<List<double>> homography; // 3x3 matrix
  final List<KeyPosition> keyPositions;

  const CalibrationData({
    required this.corners,
    required this.keyboardSize,
    required this.homography,
    required this.keyPositions,
  });

  factory CalibrationData.fromJson(Map<String, dynamic> json) {
    return CalibrationData(
      corners: KeyboardCorners.fromJson(json['corners']),
      keyboardSize: _parseKeyboardSize(json['keyboard_size']),
      homography: (json['homography'] as List)
          .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
      keyPositions: (json['key_positions'] as List)
          .map((k) => KeyPosition.fromJson(k))
          .toList(),
    );
  }

  static KeyboardSize _parseKeyboardSize(dynamic value) {
    if (value is String) {
      switch (value) {
        case 'Keys88':
          return KeyboardSize.keys88;
        case 'Keys76':
          return KeyboardSize.keys76;
        case 'Keys61':
          return KeyboardSize.keys61;
        case 'Keys49':
          return KeyboardSize.keys49;
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
