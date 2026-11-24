class Episode {
  final int number;
  final String title;
  final String description;
  final String releaseDate;
  final int durationSeconds;
  final String thumbnail;
  final String ytMain;
  final List<String> ytBackups;
  final String status;

  Episode({
    required this.number,
    required this.title,
    required this.description,
    required this.releaseDate,
    required this.durationSeconds,
    required this.thumbnail,
    required this.ytMain,
    required this.ytBackups,
    required this.status,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      number: json['epNumber'] as int,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      releaseDate: json['releaseDate'] as String? ?? '',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      thumbnail: json['thumbnail'] as String? ?? '',
      ytMain: json['yt_main'] as String? ?? '',
      ytBackups: (json['yt_backups'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: json['status'] as String? ?? 'Unknown',
    );
  }

  String get durationLabel {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m}m ${s}s';
  }
}
