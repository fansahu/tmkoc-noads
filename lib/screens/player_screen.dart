import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/episode.dart';
import '../services/episode_service.dart';

class PlayerScreen extends StatefulWidget {
  final Episode episode;
  const PlayerScreen({super.key, required this.episode});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _service = EpisodeService();
  final _yt = YoutubeExplode();

  bool _loading = true;
  String? _error;
  bool _showControls = true;
  double _speed = 1.0;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _resolveAndPlay();
  }

  Future<void> _resolveAndPlay() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final knownIds = <String>[
      if (widget.episode.ytMain.isNotEmpty) widget.episode.ytMain,
      ...widget.episode.ytBackups,
    ];

    for (final id in knownIds) {
      final url = await _resolveStreamUrl(id);
      if (url != null) {
        await _open(url);
        return;
      }
    }

    final fallbackId = await _service.findFallbackVideoId(widget.episode.number);
    if (fallbackId != null) {
      final url = await _resolveStreamUrl(fallbackId);
      if (url != null) {
        await _open(url);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
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
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _player.dispose();
    _service.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ep ${widget.episode.number}')),
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
      onScaleStart: (details) {
        _startScale = _scale;
        _startOffset = _offset;
      },
      onScaleUpdate: (details) {
        setState(() {
          _scale = (_startScale * details.scale).clamp(1.0, 3.0);
          _offset = _scale > 1.0 ? _startOffset + details.focalPointDelta : Offset.zero;
        });
      },
      onScaleEnd: (_) {
        if (_scale < 1.0) setState(() => _scale = 1.0);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform(
            transform: Matrix4.identity()
              ..translate(_offset.dx, _offset.dy)
              ..scale(_scale),
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlBar(),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _showControls = !_showControls),
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
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
                    return Slider(
                      value: dur.inMilliseconds == 0
                          ? 0
                          : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                      max: dur.inMilliseconds.toDouble(),
                      onChanged: (v) =>
                          _player.seek(Duration(milliseconds: v.toInt())),
                    );
                  },
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _player.state.playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (_player.state.playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () async {
                    await _player.seek(_player.state.position - const Duration(seconds: 10));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () async {
                    await _player.seek(_player.state.position + const Duration(seconds: 10));
                  },
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
                if (_scale != 1.0)
                  IconButton(
                    icon: const Icon(Icons.zoom_out_map, color: Colors.white),
                    onPressed: () => setState(() {
                      _scale = 1.0;
                      _offset = Offset.zero;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
