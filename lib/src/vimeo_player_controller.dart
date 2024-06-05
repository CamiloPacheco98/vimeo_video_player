import 'package:flick_video_player/flick_video_player.dart';
import 'package:video_player/video_player.dart';

class VimeoPlayerController extends VideoPlayerController {
  VimeoPlayerController.networkUrl(super.url, VideoPlayerOptions videoPlayerOptions) : super.networkUrl(videoPlayerOptions: videoPlayerOptions);

  VimeoPlayerController.file(super.file) : super.file();

  bool _mDisposed = false;
  FlickManager? _flickManager;

  void setFlickManager(FlickManager flickManager) {
    _flickManager = flickManager;
  }

  @override
  Future<void> dispose() {
    _mDisposed = true;
    return super.dispose();
  }

  Future<void> mute() async {
    return _flickManager?.flickControlManager?.mute();
  }

  bool get isDispose => _mDisposed;

  bool? get isPlaying => _flickManager?.flickVideoManager?.isPlaying;

  Future<void> exitFullScreen() async {
    if (isFullscreen == true) {
      _flickManager?.flickControlManager?.exitFullscreen();
      await Future.delayed(const Duration(milliseconds: 125));
    }
  }

  Future<void> enterFullscreen() async {
    if (isFullscreen == false) {
      _flickManager?.flickControlManager?.enterFullscreen();
      await Future.delayed(const Duration(milliseconds: 125));
    }
  }

  bool? get isFullscreen => _flickManager?.flickControlManager?.isFullscreen;
}
