import 'dart:ui';

/// Overlay style settings (mirrors Rust OverlayStyle).
class OverlayStyle {
  final Color whiteKeyColor;
  final Color blackKeyColor;
  final Color leftHandColor;
  final Color rightHandColor;
  final double stripThickness;
  final double glowStrength;
  final double glowRadius;
  final double transparency;
  final double lookaheadMs;
  final bool showBeforePlay;
  final bool showDuringPlay;
  final double fallSpeed;
  final FallDirection fallDirection;
  final bool keyHighlightEnabled;
  final Color keyHighlightColor;
  final double backgroundDim;
  final double laneOpacity;
  final bool useHandColors;

  const OverlayStyle({
    this.whiteKeyColor = const Color(0xFF4FC3F7),
    this.blackKeyColor = const Color(0xFFFF7043),
    this.leftHandColor = const Color(0xFF4FC3F7),
    this.rightHandColor = const Color(0xFFFF7043),
    this.stripThickness = 0.8,
    this.glowStrength = 0.5,
    this.glowRadius = 8.0,
    this.transparency = 0.92,
    this.lookaheadMs = 2000.0,
    this.showBeforePlay = true,
    this.showDuringPlay = true,
    this.fallSpeed = 200.0,
    this.fallDirection = FallDirection.topToBottom,
    this.keyHighlightEnabled = true,
    this.keyHighlightColor = const Color(0x40FFFFFF),
    this.backgroundDim = 0.0,
    this.laneOpacity = 0.55,
    this.useHandColors = false,
  });

  OverlayStyle copyWith({
    Color? whiteKeyColor,
    Color? blackKeyColor,
    Color? leftHandColor,
    Color? rightHandColor,
    double? stripThickness,
    double? glowStrength,
    double? glowRadius,
    double? transparency,
    double? lookaheadMs,
    bool? showBeforePlay,
    bool? showDuringPlay,
    double? fallSpeed,
    FallDirection? fallDirection,
    bool? keyHighlightEnabled,
    Color? keyHighlightColor,
    double? backgroundDim,
    double? laneOpacity,
    bool? useHandColors,
  }) {
    return OverlayStyle(
      whiteKeyColor: whiteKeyColor ?? this.whiteKeyColor,
      blackKeyColor: blackKeyColor ?? this.blackKeyColor,
      leftHandColor: leftHandColor ?? this.leftHandColor,
      rightHandColor: rightHandColor ?? this.rightHandColor,
      stripThickness: stripThickness ?? this.stripThickness,
      glowStrength: glowStrength ?? this.glowStrength,
      glowRadius: glowRadius ?? this.glowRadius,
      transparency: transparency ?? this.transparency,
      lookaheadMs: lookaheadMs ?? this.lookaheadMs,
      showBeforePlay: showBeforePlay ?? this.showBeforePlay,
      showDuringPlay: showDuringPlay ?? this.showDuringPlay,
      fallSpeed: fallSpeed ?? this.fallSpeed,
      fallDirection: fallDirection ?? this.fallDirection,
      keyHighlightEnabled: keyHighlightEnabled ?? this.keyHighlightEnabled,
      keyHighlightColor: keyHighlightColor ?? this.keyHighlightColor,
      backgroundDim: backgroundDim ?? this.backgroundDim,
      laneOpacity: laneOpacity ?? this.laneOpacity,
      useHandColors: useHandColors ?? this.useHandColors,
    );
  }

  Map<String, dynamic> toJson() => {
        'white_key_color': _colorToHex(whiteKeyColor),
        'black_key_color': _colorToHex(blackKeyColor),
        'left_hand_color': _colorToHex(leftHandColor),
        'right_hand_color': _colorToHex(rightHandColor),
        'strip_thickness': stripThickness,
        'glow_strength': glowStrength,
        'glow_radius': glowRadius,
        'transparency': transparency,
        'lookahead_ms': lookaheadMs,
        'show_before_play': showBeforePlay,
        'show_during_play': showDuringPlay,
        'fall_speed': fallSpeed,
        'fall_direction': fallDirection.name,
        'key_highlight_enabled': keyHighlightEnabled,
        'key_highlight_color': _colorToHex(keyHighlightColor),
        'background_dim': backgroundDim,
        'lane_opacity': laneOpacity,
        'use_hand_colors': useHandColors,
      };

  static String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0')}';
}

enum FallDirection {
  topToBottom,
  bottomToTop,
}

/// Sync settings for MIDI-to-video alignment.
class SyncSettings {
  final double offsetMs;
  final bool driftEnabled;
  final double driftStartMs;
  final double driftEndMs;

  const SyncSettings({
    this.offsetMs = 0.0,
    this.driftEnabled = false,
    this.driftStartMs = 0.0,
    this.driftEndMs = 0.0,
  });

  SyncSettings copyWith({
    double? offsetMs,
    bool? driftEnabled,
    double? driftStartMs,
    double? driftEndMs,
  }) {
    return SyncSettings(
      offsetMs: offsetMs ?? this.offsetMs,
      driftEnabled: driftEnabled ?? this.driftEnabled,
      driftStartMs: driftStartMs ?? this.driftStartMs,
      driftEndMs: driftEndMs ?? this.driftEndMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'offset_ms': offsetMs,
        'drift_enabled': driftEnabled,
        'drift_start_ms': driftStartMs,
        'drift_end_ms': driftEndMs,
      };

  factory SyncSettings.fromJson(Map<String, dynamic> json) {
    return SyncSettings(
      offsetMs: (json['offset_ms'] as num).toDouble(),
      driftEnabled: json['drift_enabled'] as bool,
      driftStartMs: (json['drift_start_ms'] as num).toDouble(),
      driftEndMs: (json['drift_end_ms'] as num).toDouble(),
    );
  }
}

/// Export settings.
class ExportSettings {
  final String outputPath;
  final String codec;
  final String quality;
  final bool useOriginalResolution;
  final int? customWidth;
  final int? customHeight;
  final bool useOriginalFps;
  final double? customFps;

  const ExportSettings({
    this.outputPath = '',
    this.codec = 'h264',
    this.quality = 'high',
    this.useOriginalResolution = true,
    this.customWidth,
    this.customHeight,
    this.useOriginalFps = true,
    this.customFps,
  });

  Map<String, dynamic> toJson() => {
        'output_path': outputPath,
        'codec': codec,
        'quality': quality,
        'use_original_resolution': useOriginalResolution,
        'custom_width': customWidth,
        'custom_height': customHeight,
        'use_original_fps': useOriginalFps,
        'custom_fps': customFps,
      };
}
