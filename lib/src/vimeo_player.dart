import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:vimeo_video_player/vimeo_video_player.dart';

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

    super.initState();
    _videoPlayer();
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
        ? VimeoPlayerController.networkUrl(Uri.parse(url), VideoPlayerOptions(mixWithOthers: true))
        : VimeoPlayerController.file(widget.file!);
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
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: ValueListenableBuilder(
        valueListenable: isVimeoVideoLoaded,
        builder: (context, bool isVideo, child) => Container(
          child: isVideo
              ? FlickVideoPlayer(
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
                  flickVideoWithControlsFullscreen:
                      const FlickVideoWithControls(
                    controls: FlickLandscapeControls(),
                  ),
                )
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
