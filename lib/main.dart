import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge2d/forge2d.dart' as forge2d;

void main() {
  runApp(GameWidget(game: ArcheryGame()));
}

class ArcheryGame extends Forge2DGame
    with PanDetector, MouseMovementDetector, KeyboardEvents {
  late final ArrowComponent _arrow;
  bool _isAiming = false;
  Vector2 _arrowStartPosition = Vector2.zero();
  Vector2? _dragStartPosition;
  static const double _projectileSpeed = 160.0;

  ArcheryGame()
    : super(
        gravity: forge2d.Vector2(
          0,
          9.8, // Match analytic gravity (g = 9.8)
        ),
        zoom: 1.0,
      );

  @override
  Color backgroundColor() => Colors.white;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Add coordinate axes with origin at the middle of the screen
    await add(AxesComponent());

    // Origin at center of screen for our custom axes
    final center = size / 2;

    // Arrow for aiming sits at the origin (0, 0) of our custom axes.
    const launchAngleDeg = 30.0;
    _arrowStartPosition = center;

    _arrow = ArrowComponent(startPosition: _arrowStartPosition);
    await add(_arrow);

    // Add a visual projectile path (red curve) starting exactly at the origin.
    await add(
      ProjectilePathComponent(
        startPosition: center,
        initialSpeed: 150.0,
        angleDegrees: launchAngleDeg,
        gravity: 9.8,
      ),
    );

    // Immediately shoot the arrow so that its HEAD follows the red curve.
    // _arrow.shootAlongCurve(speed: 150.0, angleDegrees: launchAngleDeg);
  }

  @override
  void onPanStart(DragStartInfo info) {
    // Allow aiming from anywhere on screen
    if (!_arrow.isFlying) {
      _isAiming = true;
      _dragStartPosition = info.eventPosition.widget;
      _aimArrowAt(info.eventPosition.widget);
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_isAiming && !_arrow.isFlying && _dragStartPosition != null) {
      final currentPosition = info.eventPosition.widget;

      _aimArrowAt(currentPosition);

      // Calculate pull strength based on distance from start position
      final aimVector = currentPosition - _arrow.startPosition;
      final aimDistance = aimVector.length;

      // Update aim direction even for small drags so the firing direction
      // always matches the visual arrow orientation.
      if (aimDistance > 0) {
        _arrow.aimDirection = aimVector.normalized();
      }

      // Only update if user has dragged away from arrow start (minimum distance)
      if (aimDistance > 20) {
        // Limit how far back you can pull
        final maxPullDistance = 200.0;
        final pullDistance = math.min(aimDistance, maxPullDistance);

        _arrow.pullStrength = pullDistance / maxPullDistance;
      }
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    if (_isAiming) {
      // _arrow.shoot();
      _isAiming = false;
      _dragStartPosition = null;
    }
  }

  @override
  void onPanCancel() {
    if (_isAiming) {
      // Reset arrow position if drag is cancelled
      _arrow.resetToStart();
      _isAiming = false;
      _dragStartPosition = null;
    }
  }

  void resetArrow() {
    _arrow.resetToStart();
  }

  void _aimArrowAt(Vector2 target) {
    if (_arrow.isFlying) return;

    final origin = _arrow.startPosition;
    final direction = target - origin;

    if (direction.length2 < 1) return;

    final angle = math.atan2(direction.y, direction.x);
    _arrow.setAimPosition(origin, angle);
    _arrow.aimDirection = direction.normalized();
  }

  @override
  void onMouseMove(PointerHoverInfo info) {
    _aimArrowAt(info.eventPosition.widget);
  }

  Future<void> _fireArrow() async {
    if (!_arrow.isLoaded) return;

    final dir = _arrow.aimDirection.normalized();
    if (dir.length2 < 1e-4) return;

    final spawnPosition = Vector2(
      _arrow.body.position.x,
      _arrow.body.position.y,
    );

    final velocity = dir * _projectileSpeed;

    await add(
      ArrowProjectile(startPosition: spawnPosition, initialVelocity: velocity),
    );
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _fireArrow();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// Draws X and Y axes with the origin at the middle of the screen.
class AxesComponent extends Component with HasGameRef<ArcheryGame> {
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final size = gameRef.size;
    final center = size / 2;

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // X-axis (horizontal) through center
    canvas.drawLine(Offset(0, center.y), Offset(size.x, center.y), paint);

    // Y-axis (vertical) through center
    canvas.drawLine(Offset(center.x, 0), Offset(center.x, size.y), paint);
  }
}

/// Draws a red parabolic projectile path for a given initial angle and speed.
class ProjectilePathComponent extends Component with HasGameRef<ArcheryGame> {
  final Vector2 startPosition;
  final double initialSpeed;
  final double angleDegrees;
  final double gravity;

  final List<Offset> _points = [];

  ProjectilePathComponent({
    required this.startPosition,
    required this.initialSpeed,
    required this.angleDegrees,
    required this.gravity,
  });

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _generatePoints();
  }

  void _generatePoints() {
    _points.clear();

    // Use the provided gravity value (positive downwards in this coordinate system)
    final g = gravity;

    // angleDegrees above horizontal means negative angle in this coordinate system (up is -y)
    final angleRad = -angleDegrees * math.pi / 180.0;

    final vx = initialSpeed * math.cos(angleRad);
    final vy = initialSpeed * math.sin(angleRad);

    // Sample the trajectory from t = 0 until the projectile comes back to the
    // same vertical level (crosses the X-axis of our custom coordinates).
    final dt = 0.01;
    final maxTime = 30.0; // safety cap

    for (double t = 0.0; t <= maxTime; t += dt) {
      final x = startPosition.x + vx * t;
      final y = startPosition.y + vy * t + 0.5 * g * t * t;

      // Stop if we go well below the bottom of the screen
      if (y > gameRef.size.y + 100) break;

      _points.add(Offset(x, y));

      // After t > 0, stop when we cross back to the original vertical level
      // (i.e. the X-axis in our custom coordinate system).
      if (t > 0 && y >= startPosition.y) {
        break;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_points.length < 2) return;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (var i = 1; i < _points.length; i++) {
      path.lineTo(_points[i].dx, _points[i].dy);
    }

    canvas.drawPath(path, paint);
  }
}

Sprite? _sharedArrowSprite;
Vector2? _sharedArrowSpriteSize;

class ArrowComponent extends BodyComponent<ArcheryGame> {
  final Vector2 startPosition;
  Vector2 aimDirection = Vector2(1, 0);
  double pullStrength = 0.0;
  bool isFlying = false;
  Vector2 spriteSize = Vector2(
    44,
    8.8,
  ); // Default size (will be updated after sprite loads)
  late SpriteComponent spriteComponent;

  // Physics constants
  static const double baseSpeed =
      15.0; // Base speed in Forge2D units per second

  ArrowComponent({required this.startPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Load sprite (re-use cached instance if available)
    _sharedArrowSprite ??= await Sprite.load('arrow.png');
    _sharedArrowSpriteSize ??= _sharedArrowSprite!.originalSize * 0.2;
    spriteSize = _sharedArrowSpriteSize!;

    // Create sprite component as child
    spriteComponent = SpriteComponent(
      sprite: _sharedArrowSprite!,
      size: spriteSize,
      // Center anchor so rotation happens around the middle of the arrow.
      anchor: Anchor.center,
    );
    add(spriteComponent);
  }

  @override
  forge2d.Body createBody() {
    // Convert Flame Vector2 to Forge2D Vector2
    final forge2dPosition = forge2d.Vector2(startPosition.x, startPosition.y);

    // Create a dynamic body (we'll control rotation during aiming)
    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.dynamic,
      position: forge2dPosition,
      angle: 0.0,
      bullet: true, // helps with fast-moving arrows
    );

    final body = world.createBody(bodyDef);

    // Create a small rectangular fixture for the arrow
    final shape = forge2d.PolygonShape()
      ..setAsBox(
        spriteSize.x / 2,
        spriteSize.y / 2,
        forge2d.Vector2.zero(),
        0.0,
      );

    final fixtureDef = forge2d.FixtureDef(shape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution =
          0.1 // Slight bounce
      ..isSensor =
          true; // Keep the aiming arrow from colliding with projectiles

    body.createFixture(fixtureDef);

    // Store reference to this component in body userData
    body.userData = this;

    // Initially, make body sleep (not affected by physics until shot)
    body.setAwake(false);
    body.gravityScale = forge2d.Vector2.zero();

    return body;
  }

  void setAimPosition(Vector2 position, double angle) {
    // Convert Flame Vector2 to Forge2D Vector2
    final forge2dPosition = forge2d.Vector2(position.x, position.y);
    // When aiming, update body position and angle without waking it up so
    // gravity doesn't pull it down while lining up the shot.
    body
      ..gravityScale = forge2d.Vector2.zero()
      ..setTransform(forge2dPosition, angle)
      ..linearVelocity = forge2d.Vector2.zero()
      ..angularVelocity = 0.0
      ..setAwake(false);
  }

  void shoot() {
    if (pullStrength > 0 && !isFlying) {
      isFlying = true;

      // Calculate initial velocity based on aim direction and pull strength
      final speed =
          baseSpeed *
          (0.5 + pullStrength * 1.5); // Speed range: 0.5x to 2x base
      final velocity = forge2d.Vector2(
        aimDirection.x * speed,
        aimDirection.y * speed,
      );

      // Apply initial velocity to the body; Box2D gravity will create the parabolic path
      body
        ..gravityScale = forge2d.Vector2(1.0, 1.0)
        ..setAwake(true)
        ..linearVelocity = velocity;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isFlying) {
      final currentVelocity = body.linearVelocity;
      if (currentVelocity.length2 > 0) {
        spriteComponent.angle = math.atan2(
          currentVelocity.y,
          currentVelocity.x,
        );
      }

      // Check if arrow goes off screen
      final gameSize = game.size;
      final pos = body.position;

      if (pos.x > gameSize.x + 100 ||
          pos.x < -100 ||
          pos.y > gameSize.y + 100 ||
          pos.y < -100) {
        // Reset arrow for next shot
        resetToStart();
        game.resetArrow();
      }
    } else {
      // Update sprite rotation during aiming
      spriteComponent.angle = body.angle;
    }
  }

  void resetToStart() {
    isFlying = false;
    pullStrength = 0.0;

    // Reset body to start position and make it sleep (not affected by physics)
    final forge2dPosition = forge2d.Vector2(startPosition.x, startPosition.y);
    body
      ..gravityScale = forge2d.Vector2.zero()
      ..setTransform(forge2dPosition, 0.0)
      ..linearVelocity = forge2d.Vector2.zero()
      ..angularVelocity = 0.0
      ..setAwake(false);
  }

  // Collision detection - this will be called by Forge2D when collision occurs
  void onCollision(forge2d.Contact contact, Object other) {
    // Handle collision with other objects
    // For example, you could check if it's a target, obstacle, etc.
    print('Arrow collided with: $other');
  }
}

class ArrowProjectile extends BodyComponent<ArcheryGame> {
  final Vector2 startPosition;
  final Vector2 initialVelocity;

  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2(44, 8.8);

  ArrowProjectile({required this.startPosition, required this.initialVelocity});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Reuse cached sprite from the aim arrow to avoid reloading the asset.
    _sharedArrowSprite ??= await Sprite.load('arrow.png');
    _sharedArrowSpriteSize ??= _sharedArrowSprite!.originalSize * 0.2;
    spriteSize = _sharedArrowSpriteSize!;

    spriteComponent = SpriteComponent(
      sprite: _sharedArrowSprite!,
      size: spriteSize,
      anchor: Anchor.center,
    );
    add(spriteComponent);
  }

  @override
  forge2d.Body createBody() {
    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.dynamic,
      position: forge2d.Vector2(startPosition.x, startPosition.y),
      angle: math.atan2(initialVelocity.y, initialVelocity.x),
      bullet: true,
    );

    final body = world.createBody(bodyDef);

    final shape = forge2d.PolygonShape()
      ..setAsBox(
        spriteSize.x / 2,
        spriteSize.y / 2,
        forge2d.Vector2.zero(),
        0.0,
      );

    final fixtureDef = forge2d.FixtureDef(shape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.1;

    body.createFixture(fixtureDef);
    body
      ..gravityScale = forge2d.Vector2(1.0, 1.0)
      ..linearVelocity = forge2d.Vector2(initialVelocity.x, initialVelocity.y);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final velocity = body.linearVelocity;
    if (velocity.length2 > 1e-4) {
      spriteComponent.angle = math.atan2(velocity.y, velocity.x);
    }

    final pos = body.position;
    final bounds = game.size;
    if (pos.x < -100 ||
        pos.x > bounds.x + 100 ||
        pos.y < -100 ||
        pos.y > bounds.y + 100) {
      removeFromParent();
    }
  }
}
