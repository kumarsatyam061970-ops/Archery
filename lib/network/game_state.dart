import 'package:flame/components.dart';

/// Synchronized game state from server
class GameState {
  Map<String, ArrowState> arrows = {};
  Map<String, PlayerState> players = {};
  int serverTick = 0;
  double serverTime = 0.0;

  void updateFromServer(Map<String, dynamic> data) {
    serverTick = data['tick'] as int? ?? 0;
    serverTime = (data['server_time'] as num?)?.toDouble() ?? 0.0;

    // Update arrows
    if (data['arrows'] != null) {
      final arrowsData = data['arrows'] as Map<String, dynamic>;
      arrows.clear();
      arrowsData.forEach((id, arrowData) {
        arrows[id] = ArrowState.fromJson(arrowData as Map<String, dynamic>);
      });
    }

    // Update players
    if (data['players'] != null) {
      final playersData = data['players'] as Map<String, dynamic>;
      players.clear();
      playersData.forEach((id, playerData) {
        players[id] = PlayerState.fromJson(playerData as Map<String, dynamic>);
      });
    }
  }
}

/// Arrow state synchronized from server
class ArrowState {
  final String id;
  final Vector2 position;
  final double angle;
  final double speed;
  final int spawnTime;
  final String? ownerId;

  ArrowState({
    required this.id,
    required this.position,
    required this.angle,
    required this.speed,
    required this.spawnTime,
    this.ownerId,
  });

  factory ArrowState.fromJson(Map<String, dynamic> json) {
    return ArrowState(
      id: json['id'] as String,
      position: Vector2(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      angle: (json['angle'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      spawnTime: json['spawn_time'] as int,
      ownerId: json['owner_id'] as String?,
    );
  }
}

/// Player state synchronized from server
class PlayerState {
  final String id;
  final Vector2 position;
  final Vector2 aimDirection;
  final int lastUpdate;

  PlayerState({
    required this.id,
    required this.position,
    required this.aimDirection,
    required this.lastUpdate,
  });

  factory PlayerState.fromJson(Map<String, dynamic> json) {
    return PlayerState(
      id: json['id'] as String,
      position: Vector2(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      aimDirection: Vector2(
        (json['aim_x'] as num?)?.toDouble() ?? 1.0,
        (json['aim_y'] as num?)?.toDouble() ?? 0.0,
      ),
      lastUpdate: json['last_update'] as int,
    );
  }
}

