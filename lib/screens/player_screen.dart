import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../models/episode.dart';
import '../services/episode_service.dart';

class PlayerScreen extends StatefulWidget {
  final Episode episode;
  final List<Episode> episodes;
  const PlayerScreen({super.key, required this.episode, this.episodes = const []});
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
  StreamSubscription<Duration>? _positionSub;
  Timer? _saveTimer;
  Timer? _upNextTimer;
  int _countdown = 5;
  bool _loading = true, _showControls = true, _fullscreen = false;
  bool _showUpNext = false, _changing = false, _fill = true;
  String? _error;
  double _speed = 1, _volume = 100, _brightness = .5;
  double _gestureStartY = 0, _gestureStartValue = 0;
  bool _brightnessGesture = false;
  List<StreamInfo> _qualities = [];
  StreamInfo? _selectedQuality;

  @override
  void initState() {
    super.initState();
    _episodes = [...widget.episodes]..sort((a,b)=>a.number.compareTo(b.number));
    _index = _episodes.indexWhere((e)=>e.number==widget.episode.number);
    if (_index < 0) { _episodes.add(widget.episode); _episodes.sort((a,b)=>a.number.compareTo(b.number)); _index=_episodes.indexWhere((e)=>e.number==widget.episode.number); }
    _episode = _episodes[_index];
    _player=Player(); _controller=VideoController(_player);
    _completedSub=_player.stream.completed.listen((v){if(v && mounted) _showNextPrompt();});
    _positionSub=_player.stream.position.listen((p){});
    _saveTimer=Timer.periodic(const Duration(seconds:5),(_)=>_savePosition());
    _loadBrightness();
    _resolveAndPlay();
  }

  String get _positionKey => 'tmkoc_position_${_episode.number}';
  Future<void> _loadBrightness() async {
    try { _brightness=await ScreenBrightness().application; if(mounted)setState((){}); } catch (_) {}
  }
  Future<void> _savePosition() async {
    if (_changing) return;
    try { final prefs=await SharedPreferences.getInstance(); await prefs.setInt(_positionKey,_player.state.position.inMilliseconds); } catch (_) {}
  }
  Future<String?> _resolve(String id) async {
    try {
      final m=await _yt.videos.streamsClient.getManifest(id);
      final muxed=m.muxed;
      if(muxed.isNotEmpty) {
        _qualities=muxed.toList()..sort((a,b)=>a.bitrate.compareTo(b.bitrate));
        return muxed.withHighestBitrate().url.toString();
      }
    } catch (_) {}
    return null;
  }
  Future<void> _resolveAndPlay() async {
    _upNextTimer?.cancel();
    if(mounted)setState(()=>{_loading=true,_error=null,_changing=true,_showUpNext=false});
    // Stop the old source immediately to prevent old audio leaking into next episode.
    try { await _player.pause(); await _player.stop(); } catch (_) {}
    String? url;
    final ids=[if(_episode.ytMain.isNotEmpty)_episode.ytMain,..._episode.ytBackups];
    for(final id in ids){ url=await _resolve(id); if(url!=null)break; }
    if(url==null){final id=await _service.findFallbackVideoId(_episode.number); if(id!=null)url=await _resolve(id);}
    if(!mounted)return;
    if(url==null){setState(()=>{_loading=false,_changing=false,_error='Stream nahi mila.'});return;}
    try {
      await _player.open(Media(url), play:false);
      await _player.setRate(_speed);
      await _player.setVolume(_volume);
      final prefs=await SharedPreferences.getInstance();
      final saved=prefs.getInt(_positionKey)??0;
      final duration=_player.state.duration;
      if(saved>0 && (duration==Duration.zero || saved<duration.inMilliseconds-3000)) {
        await _player.seek(Duration(milliseconds:saved));
      }
      await _player.play();
      if(mounted)setState(()=>{_loading=false,_changing=false});
    } catch(e) {
      if(mounted)setState(()=>{_loading=false,_changing=false,_error='Playback error: $e'});
    }
  }
  void _showNextPrompt(){
    if(_showUpNext||_changing||_index>=_episodes.length-1)return;
    setState(()=>{_showUpNext=true,_countdown=5});
    _upNextTimer=Timer.periodic(const Duration(seconds:1),(t){
      if(!mounted){t.cancel();return;}
      if(_countdown<=1){t.cancel();_next();}else{setState(()=>_countdown--);}
    });
  }
  Future<void> _next() async {
    if(_index>=_episodes.length-1||_changing)return;
    _upNextTimer?.cancel();
    await _savePosition();
    setState(()=>{_index++,_episode=_episodes[_index],_showUpNext=false});
    await _resolveAndPlay();
  }
  Future<void> _previous() async {
    if(_index<=0||_changing)return;
    _upNextTimer?.cancel();
    await _savePosition();
    setState(()=>{_index--,_episode=_episodes[_index],_showUpNext=false});
    await _resolveAndPlay();
  }
  Future<void> _toggleFullscreen() async {
    if(!_fullscreen){
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);
    }else{
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp,DeviceOrientation.portraitDown]);
    }
    if(mounted)setState(()=>_fullscreen=!_fullscreen);
  }
  Future<void> _brightnessTo(double v) async {
    _brightness=v.clamp(.02,1);
    try { await ScreenBrightness().setApplicationScreenBrightness(_brightness); } catch (_) {}
    if(mounted)setState((){});
  }
  void _onVerticalStart(DragStartDetails d, Size size) {
    _brightnessGesture=d.localPosition.dx<size.width/2;
    _gestureStartY=d.globalPosition.dy;
    _gestureStartValue=_brightnessGesture?_brightness:_volume;
  }
  void _onVerticalUpdate(DragUpdateDetails d) {
    final delta=(_gestureStartY-d.globalPosition.dy)/260;
    final value=(_gestureStartValue+delta).clamp(0.0,1.0);
    if(_brightnessGesture){_brightnessTo(value);}else{_volume=value*100;_player.setVolume(_volume);if(mounted)setState((){});}
  }
  @override
  void dispose(){
    _savePosition(); _saveTimer?.cancel(); _upNextTimer?.cancel();
    _completedSub?.cancel(); _positionSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _player.dispose(); _service.dispose(); _yt.close();
    super.dispose();
  }
  @override
  Widget build(BuildContext context)=>PopScope(
    canPop:!_fullscreen,
    onPopInvokedWithResult:(didPop,result){if(!didPop&&_fullscreen)_toggleFullscreen();},
    child:Scaffold(
      backgroundColor:Colors.black,
      appBar:_fullscreen?null:AppBar(title:Text('Ep ${_episode.number} — ${_episode.title}')),
      body:_loading?const Center(child:CircularProgressIndicator()):
        _error!=null?Center(child:Text(_error!,style:const TextStyle(color:Colors.white))):_buildVideo(),
    ),
  );
  Widget _buildVideo()=>LayoutBuilder(builder:(context,c)=>GestureDetector(
    onTap:()=>setState(()=>_showControls=!_showControls),
    onDoubleTap:(){_player.state.playing?_player.pause():_player.play();},
    onVerticalDragStart:(d)=>_onVerticalStart(d,c.biggest),
    onVerticalDragUpdate:_onVerticalUpdate,
    child:Stack(fit:StackFit.expand,children:[
      Video(controller:_controller,controls:NoVideoControls,fit:_fill?BoxFit.cover:BoxFit.contain),
      if(_showControls) ...[
        Positioned(top:10,left:12,right:12,child:Text('Episode ${_episode.number} · ${_episode.title}',style:const TextStyle(color:Colors.white,shadows:[Shadow(blurRadius:5,color:Colors.black)]))),
        Positioned(bottom:0,left:0,right:0,child:_controls()),
      ],
      if(_showUpNext&&_index<_episodes.length-1)Center(child:Container(
        padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Colors.black87,borderRadius:BorderRadius.circular(14)),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Up Next',style:TextStyle(color:Colors.white,fontSize:20)),
          Text('Episode ${_episodes[_index+1].number}',style:const TextStyle(color:Colors.white)),
          Text('$_countdown seconds',style:const TextStyle(color:Colors.white)),
          Row(mainAxisSize:MainAxisSize.min,children:[
            TextButton(onPressed:(){_upNextTimer?.cancel();setState(()=>_showUpNext=false);},child:const Text('Cancel')),
            FilledButton(onPressed:_next,child:const Text('Play now')),
          ])
        ]),
      )),
    ]),
  ));
  Widget _controls()=>Container(
    padding:const EdgeInsets.fromLTRB(10,18,10,8),
    decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.bottomCenter,end:Alignment.topCenter,colors:[Colors.black87,Colors.transparent])),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      StreamBuilder<Duration>(stream:_player.stream.position,builder:(c,p)=>StreamBuilder<Duration>(
        stream:_player.stream.duration,builder:(c,d){
          final pos=p.data??Duration.zero, dur=d.data??Duration.zero;
          return Slider(value:dur.inMilliseconds<=0?0:pos.inMilliseconds.clamp(0,dur.inMilliseconds).toDouble(),max:dur.inMilliseconds<=0?1:dur.inMilliseconds.toDouble(),onChanged:dur.inMilliseconds<=0?null:(v)=>_player.seek(Duration(milliseconds:v.toInt())));
        })),
      Row(children:[
        IconButton(onPressed:_index>0?_previous:null,icon:const Icon(Icons.skip_previous,color:Colors.white)),
        IconButton(onPressed:(){_player.state.playing?_player.pause():_player.play();setState((){});},icon:Icon(_player.state.playing?Icons.pause:Icons.play_arrow,color:Colors.white)),
        IconButton(onPressed:_index<_episodes.length-1?_next:null,icon:const Icon(Icons.skip_next,color:Colors.white)),
        IconButton(onPressed:()=>_player.seek(_player.state.position-const Duration(seconds:10)),icon:const Icon(Icons.replay_10,color:Colors.white)),
        IconButton(onPressed:()=>_player.seek(_player.state.position+const Duration(seconds:10)),icon:const Icon(Icons.forward_10,color:Colors.white)),
        const Spacer(),
        PopupMenuButton<StreamInfo>(tooltip:'Quality',icon:const Icon(Icons.hd,color:Colors.white),onSelected:(q)async{
          final pos=_player.state.position; final wasPlaying=_player.state.playing;
          setState(()=>_selectedQuality=q);
          // Re-open chosen muxed stream and restore position.
          await _player.pause(); await _player.stop(); await _player.open(Media(q.url.toString()),play:false);
          await _player.seek(pos); if(wasPlaying)await _player.play();
        },itemBuilder:(c)=>_qualities.map((q)=>PopupMenuItem(value:q,child:Text('${q.videoQuality}'))).toList()),
        IconButton(onPressed:()=>setState(()=>_fill=!_fill),icon:Icon(_fill?Icons.fit_screen:Icons.crop_free,color:Colors.white)),
        IconButton(onPressed:_toggleFullscreen,icon:Icon(_fullscreen?Icons.fullscreen_exit:Icons.fullscreen,color:Colors.white)),
      ]),
      Align(alignment:Alignment.centerRight,child:Text('Brightness ${(_brightness*100).round()}%  •  Volume ${_volume.round()}%',style:const TextStyle(color:Colors.white70,fontSize:11))),
    ]),
  );
}
