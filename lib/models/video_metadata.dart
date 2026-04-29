/// Video file metadata extracted without decoding frames.
class VideoMetadata {
  final int width;
  final int height;
  final double fps;
  final double durationMs;
  final String codec;
  final bool hasAudio;
  final int? audioSampleRate;
  final int fileSizeBytes;
  final String filePath;

  const VideoMetadata({
    required this.width,
    required this.height,
    required this.fps,
    required this.durationMs,
    required this.codec,
    required this.hasAudio,
    this.audioSampleRate,
    required this.fileSizeBytes,
    required this.filePath,
  });

  factory VideoMetadata.fromJson(Map<String, dynamic> json) {
    return VideoMetadata(
      width: json['width'] as int,
      height: json['height'] as int,
      fps: (json['fps'] as num).toDouble(),
      durationMs: (json['duration_ms'] as num).toDouble(),
      codec: json['codec'] as String,
      hasAudio: json['has_audio'] as bool,
      audioSampleRate: json['audio_sample_rate'] as int?,
      fileSizeBytes: json['file_size_bytes'] as int,
      filePath: json['file_path'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fps': fps,
        'duration_ms': durationMs,
        'codec': codec,
        'has_audio': hasAudio,
        'audio_sample_rate': audioSampleRate,
        'file_size_bytes': fileSizeBytes,
        'file_path': filePath,
      };

  String get resolution => '${width}x$height';

  String get durationFormatted {
    final seconds = durationMs ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  String get fileSizeFormatted {
    if (fileSizeBytes > 1024 * 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (fileSizeBytes > 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
  }
}
