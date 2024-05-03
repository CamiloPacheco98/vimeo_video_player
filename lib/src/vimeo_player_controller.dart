import 'package:flick_video_player/flick_video_player.dart';
import 'package:video_player/video_player.dart';

class VimeoPlayerController extends VideoPlayerController {
  VimeoPlayerController.networkUrl(super.url) : super.networkUrl();

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
}
