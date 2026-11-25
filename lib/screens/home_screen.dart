import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/episode.dart';
import '../services/episode_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = EpisodeService();
  late Future<List<Episode>> _future;
  String _query = '';
  bool _gridView = false;
  Set<int> _history = {};
  Map<int, int> _savedPositions = {};

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAll();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final history = (prefs.getStringList('tmkoc_watch_history') ?? []).map(int.parse).toSet();
    final positions = <int, int>{};
    for (final id in history) {
      final ms = prefs.getInt('tmkoc_position_$id') ?? 0;
      if (ms > 5000) positions[id] = ms;
    }
    setState(() { _history = history; _savedPositions = positions; });
  }

  Future<void> _openEpisode(Episode ep, List<Episode> all) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('tmkoc_watch_history') ?? [];
    ids.remove(ep.number.toString());
    ids.insert(0, ep.number.toString());
    await prefs.setStringList('tmkoc_watch_history', ids.take(100).toList());
    if (!mounted) return;
    setState(() => _history = ids.map(int.parse).toSet());
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(episode: ep, episodes: all)));
    _loadHistory();
  }

  List<Episode> _filter(List<Episode> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.number.toString().contains(q) ||
          e.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TMKOC — Ad Free'),
        actions: [IconButton(tooltip: _gridView ? 'List view' : 'Grid view', icon: Icon(_gridView ? Icons.view_list : Icons.grid_view), onPressed: () => setState(() => _gridView = !_gridView))],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Episode number ya title search karo',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Episode>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final episodes = _filter(snapshot.data!);
          if (episodes.isEmpty) {
            return const Center(child: Text('Kuch nahi mila'));
          }

          final recentlyAdded = [...episodes]..sort((a,b) => b.releaseDate.compareTo(a.releaseDate));
          final continueList = episodes.where((e) => _savedPositions.containsKey(e.number)).toList()..sort((a,b) => (_history.toList().indexOf(a.number)).compareTo(_history.toList().indexOf(b.number)));
          final recentList = recentlyAdded.take(8).toList();
          return Column(children: [
            if (_query.isEmpty && continueList.isNotEmpty)
              SizedBox(height: 112, child: ListView(scrollDirection: Axis.horizontal, children: continueList.map((e) => SizedBox(width: 220, child: ListTile(title: Text('Continue · Ep ${e.number}'), subtitle: Text(e.title, maxLines: 2), onTap: () => _openEpisode(e, snapshot.data!)))).toList())),
            if (_query.isEmpty && recentList.isNotEmpty)
              SizedBox(height: 72, child: ListView(scrollDirection: Axis.horizontal, children: recentList.map((e) => ActionChip(label: Text('New · Ep ${e.number}'), onPressed: () => _openEpisode(e, snapshot.data!))).toList())),
            Expanded(child: _gridView
              ? GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.65),
                  itemCount: episodes.length,
                  itemBuilder: (context, i) {
                    final ep = episodes[i];
                    return Card(child: InkWell(onTap: () => _openEpisode(ep, snapshot.data!), child: Column(children: [
                      Expanded(child: CachedNetworkImage(imageUrl: ep.thumbnail, width: double.infinity, fit: BoxFit.cover, memCacheWidth: 480, placeholder: (_,__) => Container(color: Colors.black26), errorWidget: (_,__,___) => const Icon(Icons.broken_image))),
                      Padding(padding: const EdgeInsets.all(6), child: Text('Ep ${ep.number} · ${ep.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ])));
                  })
              : ListView.builder(
            itemCount: episodes.length,
            itemBuilder: (context, i) {
              final ep = episodes[i];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: ep.thumbnail,
                    width: 96,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: Colors.grey.shade800),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image),
                  ),
                ),
                title: Text('Ep ${ep.number} — ${ep.title}'),
                subtitle: Text(
                  '${ep.releaseDate} · ${ep.durationLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _openEpisode(ep, snapshot.data!),
              );
            },
          )),
          ]);
        },
      ),
    );
  }
}
