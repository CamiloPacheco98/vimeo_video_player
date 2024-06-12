import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:vimeo_video_player/vimeo_video_player.dart';


late AudioPlayerHandler _audioHandler;
Future<void> main() async {
   _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  /// also support url like this: 'www.vimeo.com/70591644', 'vimeo.com/70591644'
  final String _vimeoVideoUrl = 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: VimeoVideoPlayer(
          url: _vimeoVideoUrl,
          autoPlay: true,
          audioHandler: _audioHandler,
        ),
      ),
    );
  }
}
