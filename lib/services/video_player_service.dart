import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_rendering.dart';

/// Service wrapping media_kit for video playback.
/// Provides a single player instance per preview session.
class VideoPlayerService {
  Player? _player;
  VideoController? _videoController;

  Player get player {
    _player ??= Player();
    return _player!;
  }

  VideoController get videoController {
    _videoController ??= VideoRendering.controllerFor(player);
    return _videoController!;
  }

  bool get isPlaying => player.state.playing;
  Duration get position => player.state.position;
  Duration get duration => player.state.duration;

  /// Open a video file for playback.
  Future<void> open(String filePath) async {
    await player.open(Media(filePath));
  }

  /// Seek to a specific position.
  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  /// Play the video.
  Future<void> play() async {
    await player.play();
  }

  /// Pause the video.
  Future<void> pause() async {
    await player.pause();
  }

  /// Toggle play/pause.
  Future<void> togglePlayPause() async {
    await player.playOrPause();
  }

  /// Dispose the player and release resources.
  void dispose() {
    _player?.dispose();
    _player = null;
    _videoController = null;
  }
}
