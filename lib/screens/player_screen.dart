import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

import '../models/episode.dart';
import '../services/episode_service.dart';

class PlayerScreen extends StatefulWidget {
  final Episode episode;
  final List<Episode> episodes;

  const PlayerScreen({
    super.key,
    required this.episode,
    required this.episodes,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _service = EpisodeService();
  final _yt = YoutubeExplode();

  late List<Episode> _episodes;
  late int _index;
  late Episode _episode;
  StreamSubscription<bool>? _completedSub;
  Timer? _upNextTimer;
  int _countdown = 5;

  bool _loading = true;
  String? _error;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _fillScreen = true;
  bool _showUpNext = false;
  bool _changingEpisode = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _episodes = [...widget.episodes]
      ..sort((a, b) => a.number.compareTo(b.number));
    _index = _episodes.indexWhere((e) => e.number == widget.episode.number);
    if (_index < 0) {
      _episodes.add(widget.episode);
      _episodes.sort((a, b) => a.number.compareTo(b.number));
      _index = _episodes.indexWhere((e) => e.number == widget.episode.number);
    }
    _episode = _episodes[_index];
    _player = Player();
    _controller = VideoController(_player);
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed && mounted) _showNextCountdown();
    });
    _resolveAndPlay();
  }

  Future<void> _resolveAndPlay() async {
    _upNextTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _showUpNext = false;
        _changingEpisode = true;
      });
    }

    final knownIds = <String>[
      if (_episode.ytMain.isNotEmpty) _episode.ytMain,
      ..._episode.ytBackups,
    ];

    for (final id in knownIds) {
      final url = await _resolveStreamUrl(id);
      if (!mounted) return;
      if (url != null) {
        await _open(url);
        return;
      }
    }

    final fallbackId = await _service.findFallbackVideoId(_episode.number);
    if (fallbackId != null && mounted) {
      final url = await _resolveStreamUrl(fallbackId);
      if (url != null && mounted) {
        await _open(url);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _changingEpisode = false;
        _error = 'Stream nahi mila — main, backups, aur search sab fail.';
      });
    }
  }

  Future<String?> _resolveStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final muxed = manifest.muxed;
      if (muxed.isNotEmpty) {
        return muxed.withHighestBitrate().url.toString();
      }
      final videoOnly = manifest.videoOnly;
      if (videoOnly.isNotEmpty) {
        return videoOnly.withHighestBitrate().url.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _open(String url) async {
    await _player.open(Media(url));
    await _player.setRate(_speed);
    if (mounted) {
      setState(() {
        _loading = false;
        _changingEpisode = false;
      });
    }
  }

  void _showNextCountdown() {
    if (_showUpNext || _changingEpisode || _index >= _episodes.length - 1) return;
    _upNextTimer?.cancel();
    setState(() {
      _showUpNext = true;
      _countdown = 5;
    });
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        _playNext();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    setState(() => _showUpNext = false);
  }

  Future<void> _playNext() async {
    if (_index >= _episodes.length - 1 || _changingEpisode) return;
    _upNextTimer?.cancel();
    setState(() {
      _index++;
      _episode = _episodes[_index];
      _showUpNext = false;
    });
    await _resolveAndPlay();
  }

  Future<void> _playPrevious() async {
    if (_index <= 0 || _changingEpisode) return;
    _upNextTimer?.cancel();
    setState(() {
      _index--;
      _episode = _episodes[_index];
      _showUpNext = false;
    });
    await _resolveAndPlay();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _leaveFullscreen() async {
    if (!_isFullscreen) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (mounted) setState(() => _isFullscreen = false);
  }

  @override
  void dispose() {
    _upNextTimer?.cancel();
    _completedSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _player.dispose();
    _service.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) _leaveFullscreen();
      },
      child: Scaffold(
        appBar: _isFullscreen
            ? null
            : AppBar(title: Text('Ep ${_episode.number} — ${_episode.title}')),
        backgroundColor: Colors.black,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center),
                    ),
                  )
                : _buildPlayer(),
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onDoubleTap: () {
        if (_player.state.playing) {
          _player.pause();
        } else {
          _player.play();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fit: _fillScreen ? BoxFit.cover : BoxFit.contain,
          ),
          if (_showControls)
            Positioned(
              left: 12,
              top: 8,
              right: 12,
              child: Text(
                'Episode ${_episode.number} · ${_episode.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlBar(),
          ),
          if (_showUpNext) _buildUpNextOverlay(),
        ],
      ),
    );
  }

  Widget _buildUpNextOverlay() {
    final next = _episodes[_index + 1];
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Up Next', style: TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 8),
            Text('Episode ${next.number} · ${next.title}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('$_countdown seconds',
                style: const TextStyle(color: Colors.white)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: _cancelUpNext, child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _playNext, child: const Text('Play now')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
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
                  final max = dur.inMilliseconds.toDouble();
                  return Slider(
                    value: max <= 0
                        ? 0
                        : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                    max: max <= 0 ? 1 : max,
                    onChanged: max <= 0
                        ? null
                        : (v) => _player.seek(Duration(milliseconds: v.toInt())),
                  );
                },
              );
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous episode',
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: _index > 0 && !_changingEpisode ? _playPrevious : null,
              ),
              IconButton(
                icon: Icon(_player.state.playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
                onPressed: () {
                  if (_player.state.playing) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                  setState(() {});
                },
              ),
              IconButton(
                tooltip: 'Next episode',
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: _index < _episodes.length - 1 && !_changingEpisode
                    ? _playNext
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () => _player.seek(
                    _player.state.position - const Duration(seconds: 10)),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () => _player.seek(
                    _player.state.position + const Duration(seconds: 10)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                  final idx = speeds.indexOf(_speed);
                  _speed = speeds[(idx + 1) % speeds.length];
                  _player.setRate(_speed);
                  setState(() {});
                },
                child: Text('${_speed.toStringAsFixed(2)}x',
                    style: const TextStyle(color: Colors.white)),
              ),
              IconButton(
                tooltip: _fillScreen ? 'Fit video' : 'Fill screen',
                icon: Icon(
                  _fillScreen ? Icons.fit_screen : Icons.crop_free,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => _fillScreen = !_fillScreen),
              ),
              IconButton(
                tooltip: 'Fullscreen',
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
