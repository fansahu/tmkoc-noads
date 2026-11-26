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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ad-Free Shows'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.deepOrange,
          labelColor: Colors.deepOrange,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'TMKOC', icon: Icon(Icons.tv)),
            Tab(text: 'FIR', icon: Icon(Icons.local_police)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SeriesView(seriesName: 'TMKOC', repoUrl: 'https://raw.githubusercontent.com/CodeMasterAbhishek/Daily-Dose-of-TMOCK/main/data/episodes.json'),
          SeriesView(seriesName: 'FIR', repoUrl: ''), 
        ],
      ),
    );
  }
}

class SeriesView extends StatefulWidget {
  final String seriesName;
  final String repoUrl;

  const SeriesView({super.key, required this.seriesName, required this.repoUrl});

  @override
  State<SeriesView> createState() => _SeriesViewState();
}

class _SeriesViewState extends State<SeriesView> {
  final _service = EpisodeService();
  late Future<List<Episode>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchSeries(widget.seriesName, widget.repoUrl);
  }

  List<Episode> _filter(List<Episode> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((e) => e.title.toLowerCase().contains(q) || e.number.toString().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: '${widget.seriesName} episode search karo...',
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
        Expanded(
          child: FutureBuilder<List<Episode>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final allEpisodes = snapshot.data ?? [];
              final filtered = _filter(allEpisodes);
              
              if (filtered.isEmpty) {
                return const Center(child: Text('Kuch nahi mila. Search karke dekho.'));
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final ep = filtered[i];
                  final originalIndex = allEpisodes.indexWhere((e) => e.number == ep.number);

                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: ep.thumbnail,
                        width: 96,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.grey.shade800),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    ),
                    title: Text('Ep ${ep.number} — ${ep.title}'),
                    subtitle: Text('${ep.releaseDate} · ${ep.durationLabel}'),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(
                          allEpisodes: allEpisodes,
                          initialIndex: originalIndex,
                          seriesName: widget.seriesName,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
