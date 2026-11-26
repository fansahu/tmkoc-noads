import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:http/http.dart' as http;
import '../models/episode.dart';
import '../services/episode_service.dart';

class PlayerScreen extends StatefulWidget {
  final List<Episode> allEpisodes;
  final int initialIndex;
  final String seriesName;

  const PlayerScreen({
    super.key,
    required this.allEpisodes,
    required this.initialIndex,
    required this.seriesName,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _service = EpisodeService();
  late SharedPreferences _prefs;

  late int _currentIndex;
  bool _loading = true;
  String? _error;
  bool _showControls = true;
  
  double _speed = 1.0;
  BoxFit _fitMode = BoxFit.contain;
  bool _isFullscreen = false;
  
  double _brightness = 1.0;
  double _volume = 1.0;
  String? _swipeIndicator; 
  Timer? _indicatorTimer;

  bool _showUpNext = false;
  int _countdown = 5;
  Timer? _countdownTimer;

  String _currentQuality = '720p';
  String _statusMessage = '';

  Episode get _currentEpisode => widget.allEpisodes[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _player = Player();
    _controller = VideoController(_player);
    
    _initApp();
  }

  Future<void> _initApp() async {
    _prefs = await SharedPreferences.getInstance();
    _brightness = await ScreenBrightness().current;
    _volume = _player.state.volume / 100.0;

    _player.stream.completed.listen((completed) {
      if (completed && mounted) {
        setState(() {
          _showUpNext = true;
          _countdown = 5;
        });
        _startCountdown();
      }
    });

    _player.stream.position.listen((pos) {
      if (pos.inSeconds % 5 == 0) {
        _prefs.setInt('progress_${widget.seriesName}_${_currentEpisode.number}', pos.inSeconds);
      }
    });

    _resolveAndPlay();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        _playNext();
      }
    });
  }

  Future<void> _resolveAndPlay() async {
    _countdownTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _showUpNext = false;
      _statusMessage = 'Resolving stream...';
    });

    final ep = _currentEpisode;
    String? videoId;

    if (ep.ytMain.startsWith('SEARCH_')) {
      videoId = await _service.findFallbackVideoId(widget.seriesName, ep.number);
    } else {
      videoId = ep.ytMain.isNotEmpty ? ep.ytMain : (ep.ytBackups.isNotEmpty ? ep.ytBackups.first : null);
    }

    if (videoId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Video nahi mila.';
        });
      }
      return;
    }

    await _loadVideo(videoId, ep.number);
  }

  Future<void> _loadVideo(String videoId, int epNum) async {
    try {
      final yt = YoutubeExplode();
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      
      if (_currentQuality == '1080p') {
        setState(() => _statusMessage = '1080p downloading (wait 10-15s)...');
        
        final videoStream = manifest.videoOnly.withHighestBitrate();
        final audioStream = manifest.audioOnly.withHighestBitrate();
        
        final tempDir = await getTemporaryDirectory();
        final videoPath = '${tempDir.path}/v_$epNum.mp4';
        final audioPath = '${tempDir.path}/a_$epNum.mp4';
        final mergedPath = '${tempDir.path}/m_$epNum.mp4';

        if (!File(mergedPath).existsSync()) {
          await _downloadStream(videoStream.url, videoPath);
          await _downloadStream(audioStream.url, audioPath);
          
          setState(() => _statusMessage = 'Merging Audio/Video (FFmpeg)...');
          await FFmpegKit.execute('-y -i $videoPath -i $audioPath -c copy $mergedPath');
        }
        
        await _startPlayer(Uri.file(mergedPath).toString(), epNum);
      } else {
        final muxed = manifest.muxed.withHighestBitrate();
        await _startPlayer(muxed.url.toString(), epNum);
      }
      yt.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  Future<void> _downloadStream(Uri url, String path) async {
    final client = http.Client();
    final req = http.Request('GET', url);
    final res = await client.send(req);
    final file = File(path);
    final sink = file.openWrite();
    await res.stream.pipe(sink);
    await sink.close();
    client.close();
  }

  Future<void> _startPlayer(String url, int epNum) async {
    await _player.open(Media(url));
    await _player.setRate(_speed);
    
    final savedPos = _prefs.getInt('progress_${widget.seriesName}_$epNum') ?? 0;
    if (savedPos > 0) {
      await _player.seek(Duration(seconds: savedPos));
    }

    if (mounted) setState(() => _loading = false);
  }

  void _playNext() {
    if (_currentIndex < widget.allEpisodes.length - 1) {
      _player.stop(); 
      setState(() {
        _currentIndex++;
        _showUpNext = false;
      });
      _resolveAndPlay();
    }
  }

  void _playPrev() {
    if (_currentIndex > 0) {
      _player.stop();
      setState(() {
        _currentIndex--;
        _showUpNext = false;
      });
      _resolveAndPlay();
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _countdownTimer?.cancel();
    _indicatorTimer?.cancel();
    _player.dispose();
    _service.dispose();
    super.dispose();
  }

  void _showSwipeIndicator(String text) {
    setState(() => _swipeIndicator = text);
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _swipeIndicator = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen ? null : AppBar(
        title: Text('${widget.seriesName} - Ep ${_currentEpisode.number}'),
        actions: [
          IconButton(icon: const Icon(Icons.screen_rotation), onPressed: _toggleFullscreen),
        ],
      ),
      backgroundColor: Colors.black,
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ),
                )
              : _buildPlayer(),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      onDoubleTapDown: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width / 2) {
          _player.seek(_player.state.position - const Duration(seconds: 10));
          _showSwipeIndicator('-10s ⏪');
        } else {
          _player.seek(_player.state.position + const Duration(seconds: 10));
          _showSwipeIndicator('+10s ⏩');
        }
      },
      onVerticalDragUpdate: (details) async {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width / 2) {
          _brightness -= details.primaryDelta! / 200;
          _brightness = _brightness.clamp(0.0, 1.0);
          await ScreenBrightness().setScreenBrightness(_brightness);
          _showSwipeIndicator('Brightness ${(_brightness * 100).toInt()}% ☀️');
        } else {
          _volume -= details.primaryDelta! / 200;
          _volume = _volume.clamp(0.0, 1.0);
          _player.setVolume(_volume * 100);
          _showSwipeIndicator('Volume ${(_volume * 100).toInt()}% 🔊');
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: FittedBox(
                fit: _fitMode,
                child: SizedBox(
                  width: 1920,
                  height: 1080,
                  child: Video(controller: _controller, controls: NoVideoControls),
                ),
              ),
            ),
          ),

          if (_swipeIndicator != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text(_swipeIndicator!, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),

          if (_showUpNext)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Up Next', style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text('Ep ${widget.allEpisodes[_currentIndex + 1].number}', style: const TextStyle(color: Colors.white, fontSize: 24)),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: _playNext, child: Text('Play in $_countdown s')),
                  ],
                ),
              ),
            ),

          if (_showControls && !_showUpNext)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildControlBar()),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: _player.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  return Slider(
                    value: dur.inMilliseconds == 0 ? 0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                    max: dur.inMilliseconds.toDouble(),
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
                  );
                },
              );
            },
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: _currentIndex > 0 ? _playPrev : null),
              IconButton(
                icon: Icon(_player.state.playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () => _player.state.playing ? _player.pause() : _player.play(),
              ),
              IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: _currentIndex < widget.allEpisodes.length - 1 ? _playNext : null),
              
              const Spacer(),
              
              TextButton(
                onPressed: () {
                  const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                  final idx = speeds.indexOf(_speed);
                  setState(() => _speed = speeds[(idx + 1) % speeds.length]);
                  _player.setRate(_speed);
                },
                child: Text('${_speed}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              
              PopupMenuButton<String>(
                icon: const Icon(Icons.high_quality, color: Colors.white),
                onSelected: (q) {
                  setState(() {
                    _currentQuality = q;
                    _resolveAndPlay();
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: '720p', child: Text('720p HD')),
                  const PopupMenuItem(value: '1080p', child: Text('1080p FHD (Slow)')),
                ],
              ),

              IconButton(
                icon: Icon(_fitMode == BoxFit.contain ? Icons.fit_screen : Icons.fullscreen, color: Colors.white),
                onPressed: () => setState(() => _fitMode = _fitMode == BoxFit.contain ? BoxFit.cover : BoxFit.contain),
              ),
              IconButton(
                icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
