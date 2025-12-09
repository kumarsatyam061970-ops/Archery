import 'dart:math' as math;
import 'package:flame/components.dart';

/// Client-side predicted arrow with reconciliation
class PredictedArrow extends PositionComponent {
  final String arrowId;
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
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update time for parabolic calculation
    t += dt;

    // Calculate parabolic position: x = x0 + v0x * t, y = y0 + v0y * t + 0.5 * g * t^2
    final angleRad = angleDeg * math.pi / 180;
    final v0 = Vector2(
      math.cos(angleRad) * speed,
      math.sin(angleRad) * speed,
    );

    final predictedX = startPos.x + v0.x * t;
    final predictedY = startPos.y + v0.y * t + 0.5 * gravity * t * t;

    // If we have server position, reconcile (smooth correction)
    if (serverPosition != null && confirmedByServer) {
      final diff = (Vector2(predictedX, predictedY) - serverPosition!).length;
      if (diff > 10.0) {
        // Significant difference - correct towards server position
        position = position + (serverPosition! - position) * 0.3;
      } else {
        position = Vector2(predictedX, predictedY);
      }
    } else {
      // Pure prediction
      position = Vector2(predictedX, predictedY);
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

    // Adjust local time to match server if needed
    final expectedTime = serverTime;
    if ((t - expectedTime).abs() > 0.1) {
      t = expectedTime;
    }
  }
}

