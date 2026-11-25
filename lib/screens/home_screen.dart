import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAll();
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

          return ListView.builder(
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(episode: ep, episodes: snapshot.data!),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
