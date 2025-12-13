import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'predicted_arrow.dart';

/// Arrow Prefab Configuration - like Unity's prefab settings
/// Configure visual, physics, and collider settings once
class ArrowPrefabConfig {
  // Visual settings
  final String spritePath;
  final double spriteScale;
  
  // Physics settings
  final double defaultSpeed;
  final double defaultGravity;
  
  // Collider settings
  final bool showColliders;
  final double colliderStrokeWidth;
  
  // Collider colors
  final Color headColor;
  final Color bodyColor;
  final Color tailColor;

  const ArrowPrefabConfig({
    this.spritePath = 'arrow.png',
    this.spriteScale = 0.2,
    this.defaultSpeed = 300.0,
    this.defaultGravity = 60.0,
    this.showColliders = true,
    this.colliderStrokeWidth = 4.0,
    this.headColor = Colors.red,
    this.bodyColor = Colors.blue,
    this.tailColor = Colors.green,
  });

  /// Default arrow prefab configuration
  static const ArrowPrefabConfig defaultConfig = ArrowPrefabConfig();
}

/// Arrow Prefab - like Unity's prefab system
/// Configure once, instantiate many times
class ArrowPrefab {
  final ArrowPrefabConfig config;

  ArrowPrefab({ArrowPrefabConfig? config})
      : config = config ?? ArrowPrefabConfig.defaultConfig;

  /// Instantiate an arrow at the given position and angle
  /// This is like Unity's Instantiate(prefab, position, rotation)
  PredictedArrow instantiate({
    required String arrowId,
    required Vector2 position,
    required double angleDeg,
    double? speed,
    double? gravity,
    int? spawnTimestamp,
  }) {
    return PredictedArrow(
      arrowId: arrowId,
      startPos: position,
      angleDeg: angleDeg,
      speed: speed ?? config.defaultSpeed,
      gravity: gravity ?? config.defaultGravity,
      spawnTimestamp: spawnTimestamp ?? DateTime.now().millisecondsSinceEpoch,
      prefabConfig: config, // Pass config to arrow
    );
  }

  /// Create arrow with current time as spawn timestamp
  PredictedArrow create({
    required String arrowId,
    required Vector2 position,
    required double angleDeg,
    double? speed,
    double? gravity,
  }) {
    return instantiate(
      arrowId: arrowId,
      position: position,
      angleDeg: angleDeg,
      speed: speed,
      gravity: gravity,
    );
  }
}

