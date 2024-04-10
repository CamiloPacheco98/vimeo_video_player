import 'package:video_player/video_player.dart';

class VimeoPlayerController extends VideoPlayerController {
  VimeoPlayerController.networkUrl(super.url) : super.networkUrl();

  bool _mDisposed = false;

  @override
  Future<void> dispose() {
    _mDisposed = true;
    return super.dispose();
  }

  bool get isDispose => _mDisposed;
}
