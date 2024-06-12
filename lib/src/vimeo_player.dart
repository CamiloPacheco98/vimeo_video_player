import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vimeo_video_player/vimeo_video_player.dart';
import 'package:audio_service/audio_service.dart';

import 'vimeo_player_controller.dart';

class VimeoVideoPlayer extends StatefulWidget {
  /// vimeo video url
  final String? url;
  final File? file;

  /// hide/show device status-bar
  final List<SystemUiOverlay> systemUiOverlay;

  /// deviceOrientation of video view
  final List<DeviceOrientation> deviceOrientation;

  /// If this value is set, video will have initial position
  /// set to given minute/second.
  ///
  /// Incorrect values (exceeding the video duration) will be ignored.
  final Duration? startAt;

  /// If this function is provided, it will be called periodically with
  /// current video position (approximately every 500 ms).
  final void Function(Duration timePoint)? onProgress;

  /// If this function is provided, it will be called when video
  /// finishes playback.
  final VoidCallback? onFinished;

  /// to auto-play the video once initialized
  final bool autoPlay;

  final bool exitFullScreenOnFinish;

  /// Options to pass in Dio GET request
  /// Used in vimeo video public API call to get the video config
  final Options? dioOptionsForVimeoVideoConfig;

  final void Function(VimeoPlayerController? controller)? onReadyController;

  final VoidCallback? onNoSourceFound;

  final bool hideControls;

  final AudioPlayerHandler? audioHandler;

  const VimeoVideoPlayer({
    this.url,
    this.file,
    this.systemUiOverlay = const [
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ],
    this.deviceOrientation = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
    this.startAt,
    this.onProgress,
    this.onFinished,
    this.autoPlay = false,
    this.dioOptionsForVimeoVideoConfig,
    this.onReadyController,
    this.onNoSourceFound,
    super.key,
    this.exitFullScreenOnFinish = true,
    this.hideControls = false,
    this.audioHandler,
  });

  @override
  State<VimeoVideoPlayer> createState() => _VimeoVideoPlayerState();
}

class _VimeoVideoPlayerState extends State<VimeoVideoPlayer> {
  /// video player controller
  VimeoPlayerController? _videoPlayerController;

  final VideoPlayerController _emptyVideoPlayerController =
      VideoPlayerController.networkUrl(Uri.parse(''));

  /// flick manager to manage the flick player
  FlickManager? _flickManager;

  /// used to notify that video is loaded or not
  ValueNotifier<bool> isVimeoVideoLoaded = ValueNotifier(false);

  /// used to check that the video is already seeked or not
  bool _isSeekedVideo = false;

  @override
  void initState() {
    if (widget.url == null && widget.file == null) {
      throw "Invalid source. The url or file should not be null";
    }
    _videoPlayer();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant VimeoVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url == null && widget.file == null) {
      throw "Invalid source. The url or file should not be null";
    }

    if (oldWidget.url != widget.url) {
      _onChangedVideoSource();
    } else if (oldWidget.file != widget.file && widget.file != null) {
      _onChangedVideoSource();
    }
  }

  void _onChangedVideoSource() async {
    if (_videoPlayerController?.isPlaying == true) {
      await _videoPlayerController?.pause();
      await _videoPlayerController?.dispose();
    }
    isVimeoVideoLoaded.value = false;
    _videoPlayer();
  }

  @override
  void deactivate() {
    _videoPlayerController?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    /// disposing the controllers
    widget.audioHandler?.playbackState.close();
    _flickManager = null;
    _flickManager?.dispose();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _emptyVideoPlayerController.dispose();
    isVimeoVideoLoaded.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    ); // to re-show bars
    super.dispose();
  }

  void _setVideoInitialPosition() {
    final Duration? startAt = widget.startAt;

    if (startAt != null && _videoPlayerController != null) {
      _videoPlayerController!.addListener(() {
        final VideoPlayerValue videoData = _videoPlayerController!.value;
        if (videoData.isInitialized &&
            videoData.duration > startAt &&
            !_isSeekedVideo) {
          _videoPlayerController!.seekTo(startAt);
          _isSeekedVideo = true;
        } // else ignore, incorrect value
      });
    }
  }

  void _setVideoListeners() {
    final onProgressCallback = widget.onProgress;
    final onFinishCallback = widget.onFinished;

    if (_videoPlayerController != null &&
        (onProgressCallback != null || onFinishCallback != null)) {
      _videoPlayerController!.addListener(() async {
        final VideoPlayerValue videoData = _videoPlayerController!.value;
        if (videoData.isInitialized) {
          if (videoData.isPlaying) {
            if (onProgressCallback != null) {
              onProgressCallback.call(videoData.position);
            }
          } else if (videoData.duration == videoData.position) {
            if (widget.exitFullScreenOnFinish) {
              await _videoPlayerController?.exitFullScreen();
            }
            if (onFinishCallback != null) {
              onFinishCallback.call();
            }
          }
        }
      });
    }
  }

  void _videoPlayer() {
    var url = widget.url;
    // ignore: avoid_print
    print("(vimeo player) play video with url: $url");
    _videoPlayerController = url != null
        ? VimeoPlayerController.networkUrl(
            Uri.parse(url), VideoPlayerOptions(allowBackgroundPlayback: true))
        : VimeoPlayerController.file(widget.file!);
    _videoPlayerController?.initialize().then((value) {
      final _audioHandler = widget.audioHandler;
      if (_audioHandler != null) {
        _audioHandler.setVideoFunctions(_videoPlayerController!.play,
            _videoPlayerController!.pause, _videoPlayerController!.seekTo, () {
          _videoPlayerController!.seekTo(Duration.zero);
          _videoPlayerController!.pause();
        });

        // So that our clients (the Flutter UI and the system notification) know
        // what state to display, here we set up our audio handler to broadcast all
        // playback state changes as they happen via playbackState...
        _audioHandler.initializeStreamController(_videoPlayerController);
        _audioHandler.playbackState
            .addStream(_audioHandler.streamController.stream);
      }
      _setVideoInitialPosition();
      _setVideoListeners();

      widget.onReadyController?.call(_videoPlayerController!);

      _flickManager = FlickManager(
        videoPlayerController:
            _videoPlayerController ?? _emptyVideoPlayerController,
        autoPlay: widget.autoPlay,
        // ignore: use_build_context_synchronously
      )..registerContext(context);

      _videoPlayerController!.setFlickManager(_flickManager!);
      isVimeoVideoLoaded.value = !isVimeoVideoLoaded.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: ValueListenableBuilder(
        valueListenable: isVimeoVideoLoaded,
        builder: (context, bool isVideo, child) => Container(
          child: isVideo
              ? flickVideoPlayerView()
              : const Center(
                  child: CircularProgressIndicator(
                    color: Colors.grey,
                    backgroundColor: Colors.white,
                  ),
                ),
        ),
      ),
      onPopInvoked: (didPop) {
        /// pausing the video before the navigator pop
        _videoPlayerController?.pause();
      },
    );
  }

  Widget flickVideoPlayerView() {
    return widget.hideControls
        ? FlickVideoPlayer(
            key: ObjectKey(_flickManager),
            flickManager: _flickManager ??
                FlickManager(
                  videoPlayerController: _emptyVideoPlayerController,
                ),
            systemUIOverlay: widget.systemUiOverlay,
            preferredDeviceOrientation: widget.deviceOrientation,
            flickVideoWithControls: const FlickVideoWithControls(
              controls: null,
            ),
            flickVideoWithControlsFullscreen:
                const FlickVideoWithControls(controls: null),
          )
        : FlickVideoPlayer(
            key: ObjectKey(_flickManager),
            flickManager: _flickManager ??
                FlickManager(
                  videoPlayerController: _emptyVideoPlayerController,
                ),
            systemUIOverlay: widget.systemUiOverlay,
            preferredDeviceOrientation: widget.deviceOrientation,
            flickVideoWithControls: const FlickVideoWithControls(
              videoFit: BoxFit.fitWidth,
              controls: FlickPortraitControls(),
            ),
            flickVideoWithControlsFullscreen: const FlickVideoWithControls(
              controls: FlickLandscapeControls(),
            ),
          );
  }
}

// ignore: library_private_types_in_public_api
extension ShowAlertDialog on _VimeoVideoPlayerState {
  showAlertDialog(BuildContext context) {
    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: const Text("Alert"),
      content: const Text("Some thing wrong with this url"),
      actions: [
        TextButton(
          child: const Text("OK"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}

/// An [AudioHandler] for playing a single item.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  late StreamController<PlaybackState> streamController;

  static final _item = MediaItem(
    id: 'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3',
    album: "Science Friday",
    title: "A Salute To Head-Scratching Science",
    artist: "Science Friday and WNYC Studios",
    duration: const Duration(milliseconds: 5739820),
    artUri: Uri.parse(
        'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg'),
  );

  Function? _videoPlay;
  Function? _videoPause;
  Function? _videoSeek;
  Function? _videoStop;

  void setVideoFunctions(
      Function play, Function pause, Function seek, Function stop) {
    _videoPlay = play;
    _videoPause = pause;
    _videoSeek = seek;
    _videoStop = stop;
    mediaItem.add(_item);
  }

  /// Initialise our audio handler.
  AudioPlayerHandler();

  // In this simple example, we handle only 4 actions: play, pause, seek and
  // stop. Any button press from the Flutter UI, notification, lock screen or
  // headset will be routed through to these 4 methods so that you can handle
  // your audio playback logic in one place.

  @override
  Future<void> play() async => _videoPlay!();

  @override
  Future<void> pause() async => _videoPause!();

  @override
  Future<void> seek(Duration position) async => _videoSeek!(position);

  @override
  Future<void> stop() async => _videoStop!();

  void initializeStreamController(
      VideoPlayerController? videoPlayerController) {
    bool _isPlaying() => videoPlayerController?.value.isPlaying ?? false;

    AudioProcessingState _processingState() {
      if (videoPlayerController == null) return AudioProcessingState.idle;
      if (videoPlayerController.value.isInitialized)
        return AudioProcessingState.ready;
      return AudioProcessingState.idle;
    }

    Duration _bufferedPosition() {
      DurationRange? currentBufferedRange =
          videoPlayerController?.value.buffered.firstWhere((durationRange) {
        Duration position = videoPlayerController.value.position;
        bool isCurrentBufferedRange =
            durationRange.start < position && durationRange.end > position;
        return isCurrentBufferedRange;
      });
      if (currentBufferedRange == null) return Duration.zero;
      return currentBufferedRange.end;
    }

    void _addVideoEvent() {
      streamController.add(PlaybackState(
        controls: [
          MediaControl.rewind,
          if (_isPlaying()) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _processingState(),
        playing: _isPlaying(),
        updatePosition: videoPlayerController?.value.position ?? Duration.zero,
        bufferedPosition: _bufferedPosition(),
        speed: videoPlayerController?.value.playbackSpeed ?? 1.0,
      ));
    }

    void startStream() {
      videoPlayerController?.addListener(_addVideoEvent);
    }

    void stopStream() {
      videoPlayerController?.removeListener(_addVideoEvent);
      streamController.close();
    }

    streamController = StreamController<PlaybackState>(
        onListen: startStream,
        onPause: stopStream,
        onResume: startStream,
        onCancel: stopStream);
  }
}
