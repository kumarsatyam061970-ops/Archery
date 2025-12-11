import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/collisions.dart';

/// Client-side predicted arrow with reconciliation
class PredictedArrow extends PositionComponent 
    with HasGameRef, CollisionCallbacks {
  String arrowId; // Mutable so we can update it when server assigns ID
  final Vector2 startPos;
  final double angleDeg;
  final double speed;
  final double gravity;
  final int spawnTimestamp;

  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2(44, 8.8);

  double t = 0.0; // Time elapsed since spawn
  bool confirmedByServer = false;
  Vector2? serverPosition; // Last known server position for reconciliation

  PredictedArrow({
    required this.arrowId,
    required this.startPos,
    required this.angleDeg,
    required this.speed,
    required this.gravity,
    required this.spawnTimestamp,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final sprite = await Sprite.load('arrow.png');
    final originalSize = sprite.originalSize;
    spriteSize = originalSize * 0.2;

    final angleRad = angleDeg * math.pi / 180;
    spriteComponent = SpriteComponent(
      sprite: sprite,
      size: spriteSize,
      anchor: Anchor.center,
      angle: angleRad,
    );
    add(spriteComponent);

    position = startPos;

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
}

