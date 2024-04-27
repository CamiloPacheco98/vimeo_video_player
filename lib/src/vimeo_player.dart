import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flick_video_player/flick_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'model/vimeo_video_config.dart';
import 'vimeo_player_controller.dart';

class VimeoVideoPlayer extends StatefulWidget {
  /// vimeo video url
  final String url;

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

  /// Options to pass in Dio GET request
  /// Used in vimeo video public API call to get the video config
  final Options? dioOptionsForVimeoVideoConfig;

  final void Function(VimeoPlayerController? controller)? onReadyController;

  final VoidCallback? onNoSourceFound;

  final bool skipVimeoConfigFetch;

  const VimeoVideoPlayer({
    required this.url,
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
    this.skipVimeoConfigFetch = false,
    super.key,
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

  final RegExp _vimeoRegExp = RegExp(
    r'^(?:http|https)?:?/?/?(?:www\.)?(?:player\.)?vimeo\.com/(?:channels/(?:\w+/)?|groups/[^/]*/videos/|video/|)(\d+)(?:|/\?)?$',
    caseSensitive: false,
    multiLine: false,
  );

  /// used to check that the url format is valid vimeo video format
  bool get _isVimeoVideo {
    // ignore: avoid_print
    print("(vimeo player) checking if the url: ${widget.url} is a vimeo url");
    var regExp = _vimeoRegExp;
    final match = regExp.firstMatch(widget.url);
    if (match != null && match.groupCount >= 1) return true;
    return false;
  }

  /// used to check that the video is already seeked or not
  bool _isSeekedVideo = false;

  @override
  void initState() {
    super.initState();

    /// checking that vimeo url is valid or not
    if (_isVimeoVideo) {
      _videoPlayer();
    } else if (widget.skipVimeoConfigFetch) {
      _playWithUrl(widget.url);
      // ignore: avoid_print
      print("(vimeo player) is not a vimeo url");
    }
  }

  @override
  void didUpdateWidget(covariant VimeoVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      if (_isVimeoVideo || widget.skipVimeoConfigFetch) {
        isVimeoVideoLoaded.value = false;
        _videoPlayer();
      }
    }
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
      _videoPlayerController!.addListener(() {
        final VideoPlayerValue videoData = _videoPlayerController!.value;
        if (videoData.isInitialized) {
          if (videoData.isPlaying) {
            if (onProgressCallback != null) {
              onProgressCallback.call(videoData.position);
            }
          } else if (videoData.duration == videoData.position) {
            if (onFinishCallback != null) {
              onFinishCallback.call();
            }
          }
        }
      });
    }
  }

  void _videoPlayer() {
    if (widget.skipVimeoConfigFetch) {
      _playWithUrl(widget.url);
      return;
    }

    /// getting the vimeo video configuration from api and setting managers
    _getVimeoVideoConfigFromUrl(widget.url).then((value) async {
      final progressiveList = value?.request?.files?.progressive ?? [];

      var vimeoMp4Video = '';

      if (progressiveList.isEmpty) {
        widget.onNoSourceFound?.call();
      } else {
        progressiveList.map((element) {
          if (element.isValidUrl && vimeoMp4Video == '') {
            vimeoMp4Video = element.url ?? '';
          }
        }).toList();
        if (vimeoMp4Video.isEmpty || vimeoMp4Video.trim().isEmpty) {
          widget.onNoSourceFound?.call();
          // showAlertDialog(context);
        }
      }
      _playWithUrl(vimeoMp4Video);
    });
  }

  void _playWithUrl(String url) {
    // ignore: avoid_print
    print("(vimeo player) play video with url: $url");
    _videoPlayerController = VimeoPlayerController.networkUrl(Uri.parse(url));
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

  /// used to get valid vimeo video configuration
  Future<VimeoVideoConfig?> _getVimeoVideoConfigFromUrl(
    String url, {
    bool trimWhitespaces = true,
  }) async {
    if (trimWhitespaces) url = url.trim();

    final response = await _getVimeoVideoConfig(vimeoVideoId: _videoId);
    return (response != null) ? response : null;
  }

  /// give vimeo video configuration from api
  Future<VimeoVideoConfig?> _getVimeoVideoConfig({
    required String vimeoVideoId,
  }) async {
    try {
      Response responseData = await Dio().get(
        'https://player.vimeo.com/video/$vimeoVideoId/config',
        options: widget.dioOptionsForVimeoVideoConfig,
      );
      var vimeoVideo = VimeoVideoConfig.fromJson(responseData.data);
      return vimeoVideo;
    } on DioException catch (e) {
      log('Dio Error : ', name: e.error.toString());
      return null;
    } on Exception catch (e) {
      log('Error : ', name: e.toString());
      return null;
    }
  }

  String get _videoId {
    RegExpMatch? match = _vimeoRegExp.firstMatch(widget.url);
    return match?.group(1) ?? '';
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
