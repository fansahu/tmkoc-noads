import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/episode.dart';

class EpisodeService {
  static const _csvUrl = 'https://raw.githubusercontent.com/CodeMasterAbhishek/Daily-Dose-of-TMOCK/main/data/episodes.csv';
  static const _jsonUrl = 'https://raw.githubusercontent.com/CodeMasterAbhishek/Daily-Dose-of-TMOCK/main/data/episodes.json';

  final _yt = YoutubeExplode();

  Future<List<Episode>> fetchSeries(String seriesName, String repoUrl) async {
    // Agar TMKOC hai, to repo se fetch karo
    if (seriesName == 'TMKOC') {
      for (final url in [_jsonUrl, _csvUrl]) {
        try {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode != 200) continue;

          if (url.endsWith('.json')) {
            final map = jsonDecode(res.body) as Map<String, dynamic>;
            final list = map.values.map((e) => Episode.fromJson(e as Map<String, dynamic>)).toList();
            list.sort((a, b) => a.number.compareTo(b.number));
            return list;
          }

          final lines = const LineSplitter().convert(res.body);
          if (lines.isEmpty) continue;
          final headers = lines.first.split(',');
          final idx = {for (var i = 0; i < headers.length; i++) headers[i].trim(): i};

          final episodes = <Episode>[];
          for (final line in lines.skip(1)) {
            if (line.trim().isEmpty) continue;
            final cells = line.split(',');
            String cell(String key) => (idx[key] != null && idx[key]! < cells.length) ? cells[idx[key]!].trim() : '';

            final numStr = cell('epNumber').isNotEmpty ? cell('epNumber') : cell('number');
            if (numStr.isEmpty) continue;

            episodes.add(Episode(
              number: int.tryParse(numStr) ?? 0,
              title: cell('title'),
              description: cell('description'),
              releaseDate: cell('releaseDate'),
              durationSeconds: int.tryParse(cell('durationSeconds')) ?? 0,
              thumbnail: cell('thumbnail'),
              ytMain: cell('yt_main').isNotEmpty ? cell('yt_main') : cell('ytMain'),
              ytBackups: cell('yt_backups').isNotEmpty ? cell('yt_backups').split('|').where((s) => s.trim().isNotEmpty).toList() : [],
              status: cell('status').isNotEmpty ? cell('status') : 'Unknown',
            ));
          }
          episodes.sort((a, b) => a.number.compareTo(b.number));
          return episodes;
        } catch (_) {
          continue;
        }
      }
    }
    
    // FIR ya baaki series ke liye Auto-search list generate hogi
    return _generateSearchList(seriesName);
  }

  Future<List<Episode>> _generateSearchList(String seriesName) async {
    List<Episode> list = [];
    for (int i = 1; i <= 500; i++) {
      list.add(Episode(
        number: i,
        title: '$seriesName Episode $i',
        description: 'Auto-search episode',
        releaseDate: 'Recent',
        durationSeconds: 1200,
        thumbnail: 'https://via.placeholder.com/150',
        ytMain: 'SEARCH_$i', 
        ytBackups: [],
        status: 'Auto',
      ));
    }
    return list;
  }

  Future<String?> findFallbackVideoId(String seriesName, int episodeNumber) async {
    try {
      final query = '$seriesName episode $episodeNumber full episode';
      final results = await _yt.search.search(query);
      for (final r in results) {
        if (r is SearchVideo) return r.id.value;
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _yt.close();
}
