// lib/screens/leagues/team_models.dart

class TeamPlayer {
  final String id;
  final String name;

  TeamPlayer({required this.id, required this.name});

  factory TeamPlayer.fromMap(String id, Map<String, dynamic> m) =>
      TeamPlayer(id: id, name: (m['name'] as String?) ?? id);

  Map<String, dynamic> toMap() => {'name': name};
}
