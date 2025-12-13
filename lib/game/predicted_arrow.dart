import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'arrow_prefab.dart';

/// Client-side predicted arrow with reconciliation
class PredictedArrow extends PositionComponent 
    with HasGameRef, CollisionCallbacks {
  String arrowId; // Mutable so we can update it when server assigns ID
  final Vector2 startPos;
  final double angleDeg;
  final double speed;
  final double gravity;
  final int spawnTimestamp;
  final ArrowPrefabConfig? prefabConfig; // Prefab configuration

  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2(44, 8.8);

  double t = 0.0; // Time elapsed since spawn
  bool confirmedByServer = false;
  Vector2? serverPosition; // Last known server position for reconciliation

  // Collider vertices (relative to arrow center, arrow points right)
  late List<Vector2> headVertices;
  late List<Vector2> bodyVertices;
  late List<Vector2> tailVertices;

  PredictedArrow({
    required this.arrowId,
    required this.startPos,
    required this.angleDeg,
    required this.speed,
    required this.gravity,
    required this.spawnTimestamp,
    this.prefabConfig, // Add prefab config parameter
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Use prefab config if available, otherwise use defaults
    final spritePath = prefabConfig?.spritePath ?? 'arrow.png';
    final spriteScale = prefabConfig?.spriteScale ?? 0.2;

    final sprite = await Sprite.load(spritePath);
    final originalSize = sprite.originalSize;
    spriteSize = originalSize * spriteScale;

    final angleRad = angleDeg * math.pi / 180;
    spriteComponent = SpriteComponent(
      sprite: sprite,
      size: spriteSize,
      anchor: Anchor.center,
      angle: angleRad,
    );
    add(spriteComponent);

    position = startPos;

    // Initialize collider vertices
    _initializeColliderVertices();

    // Add small collision point at arrow head (tip of arrow)
    // Arrow head is at the front (positive X in arrow's local space)
    final arrowHeadOffset = Vector2(spriteSize.x / 2, 0); // Tip of arrow
    
    // Use a small circle hitbox at the arrow head for precise collision
    add(CircleHitbox(
      radius: 2.0, // Small radius for precise collision detection
      position: arrowHeadOffset,
      anchor: Anchor.center,
    ));
  }

  void _initializeColliderVertices() {
    final arrowLength = spriteSize.x; // 8.8
    final arrowWidth = spriteSize.y; // ~1.76
    final headLength = arrowLength * 0.3; // ~2.64 (front 30%)
    final tailLength = arrowLength * 0.3; // ~2.64 (back 30%)

    // Head (arrow tip) - triangular shape at the front
    headVertices = [
      Vector2(arrowLength / 2, 0), // Tip (rightmost point)
      Vector2(arrowLength / 2 - headLength, -arrowWidth / 2), // Top left
      Vector2(arrowLength / 2 - headLength, arrowWidth / 2), // Bottom left
    ];

    // Body (middle section) - rectangular shape
    bodyVertices = [
      Vector2(arrowLength / 2 - headLength, -arrowWidth / 2), // Top left
      Vector2(-arrowLength / 2 + tailLength, -arrowWidth / 2), // Top right
      Vector2(-arrowLength / 2 + tailLength, arrowWidth / 2), // Bottom right
      Vector2(arrowLength / 2 - headLength, arrowWidth / 2), // Bottom left
    ];

    // Tail (fletching) - wider at the back
    tailVertices = [
      Vector2(-arrowLength / 2 + tailLength, -arrowWidth / 2), // Top left
      Vector2(-arrowLength / 2, -arrowWidth), // Top right (wider)
      Vector2(-arrowLength / 2, arrowWidth), // Bottom right (wider)
      Vector2(-arrowLength / 2 + tailLength, arrowWidth / 2), // Bottom left
    ];

    print('🏹 [ARROW] Collider vertices initialized. Head: ${headVertices.length}, Body: ${bodyVertices.length}, Tail: ${tailVertices.length}');
  }

  /// Get arrow head position in world space
  Vector2 getArrowHeadPosition() {
    final angleRad = spriteComponent.angle;
    final arrowLength = spriteSize.x / 2;
    return position + Vector2(
      math.cos(angleRad) * arrowLength,
      math.sin(angleRad) * arrowLength,
    );
  }

  @override
  bool onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    // Server is authoritative - just log for debugging
    print('🏹 [ARROW] Collision detected');
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Calculate elapsed time since spawn
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final elapsedSeconds = (currentTime - spawnTimestamp) / 1000.0;
    
    // Use elapsed time for calculation (don't just increment t)
    t = elapsedSeconds;

    // Calculate parabolic position: x = x0 + v0x * t, y = y0 + v0y * t + 0.5 * g * t^2
    final angleRad = angleDeg * math.pi / 180;
    final v0 = Vector2(
      math.cos(angleRad) * speed,
      math.sin(angleRad) * speed,
    );

    final predictedX = startPos.x + v0.x * t;
    final predictedY = startPos.y + v0.y * t + 0.5 * gravity * t * t;

    // Always use pure prediction - the arrow should move forward based on physics
    // Server reconciliation only happens if there's a significant desync
    final predictedPos = Vector2(predictedX, predictedY);
    
    // Use prediction unless server has significantly different position
    if (serverPosition != null && confirmedByServer && t > 0.1) {
      final diff = (predictedPos - serverPosition!).length;
      if (diff > 50.0) {
        // Large desync - but only correct if server is ahead
        final predictedDist = (predictedPos - startPos).length;
        final serverDist = (serverPosition! - startPos).length;
        
        if (serverDist > predictedDist * 0.9) {
          // Server is ahead - gently correct
          position = position + (serverPosition! - position) * 0.1;
        } else {
          // Our prediction is ahead - trust it
          position = predictedPos;
        }
      } else {
        // Small difference - use our prediction
        position = predictedPos;
      }
    } else {
      // No server data or early phase - use pure prediction
      position = predictedPos;
    }

    // Update sprite angle based on velocity direction
    final vx = v0.x;
    final vy = v0.y + gravity * t;
    if (vx * vx + vy * vy > 1e-6) {
      spriteComponent.angle = math.atan2(vy, vx);
    }
  }

  /// Reconcile with server state
  void reconcileWithServer(Vector2 serverPos, double serverTime) {
    serverPosition = serverPos;
    confirmedByServer = true;
    // Don't modify t here - it's calculated from elapsed time in update()
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Only render colliders if enabled in prefab config
    if (prefabConfig?.showColliders ?? true) {
      // Save canvas state
      canvas.save();

      // Translate to arrow position and rotate
      canvas.translate(position.x, position.y);
      canvas.rotate(spriteComponent.angle);

      // Use prefab config colors and stroke width if available
      final headPaint = Paint()
        ..color = prefabConfig?.headColor ?? Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = prefabConfig?.colliderStrokeWidth ?? 4.0;

      final bodyPaint = Paint()
        ..color = prefabConfig?.bodyColor ?? Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = prefabConfig?.colliderStrokeWidth ?? 4.0;

      final tailPaint = Paint()
        ..color = prefabConfig?.tailColor ?? Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = prefabConfig?.colliderStrokeWidth ?? 4.0;

      // Draw head collider (red)
      if (headVertices.isNotEmpty) {
        _drawPolygon(canvas, headVertices, headPaint);
      }

      // Draw body collider (blue)
      if (bodyVertices.isNotEmpty) {
        _drawPolygon(canvas, bodyVertices, bodyPaint);
      }

      // Draw tail collider (green)
      if (tailVertices.isNotEmpty) {
        _drawPolygon(canvas, tailVertices, tailPaint);
      }

      // Restore canvas state
      canvas.restore();
    }
  }

  void _drawPolygon(Canvas canvas, List<Vector2> vertices, Paint paint) {
    if (vertices.length < 2) return;

    final path = Path();
    path.moveTo(vertices.first.x, vertices.first.y);
    for (var i = 1; i < vertices.length; i++) {
      path.lineTo(vertices[i].x, vertices[i].y);
    }
    path.close();

    canvas.drawPath(path, paint);

    // Debug: Draw vertex points
    final vertexPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (final vertex in vertices) {
      canvas.drawCircle(Offset(vertex.x, vertex.y), 2, vertexPaint);
    }
  }
}

