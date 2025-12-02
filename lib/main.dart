import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:forge2d/forge2d.dart' as forge2d;

void main() {
  runApp(GameWidget(game: ArcheryGame()));
}

class ArcheryGame extends Forge2DGame with PanDetector {
  late final ArrowComponent _arrow;
  bool _isAiming = false;
  Vector2 _arrowStartPosition = Vector2.zero();
  Vector2? _dragStartPosition;

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

    // Arrow starts near the origin (0,0) of our custom axes.
    // We'll aim it so that its HEAD is exactly at the origin.
    const launchAngleDeg = 30.0;
    final launchAngleRad = -launchAngleDeg * math.pi / 180.0;
    final launchDir = Vector2(
      math.cos(launchAngleRad),
      math.sin(launchAngleRad),
    );

    // Approximate arrow length (matches ArrowComponent's default).
    const arrowLength = 44.0;

    // Tail position so that the head lies at the origin (center).
    final tailPosition = center - launchDir * arrowLength;
    _arrowStartPosition = tailPosition;

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
    _arrow.shootAlongCurve(speed: 150.0, angleDegrees: launchAngleDeg);
  }

  @override
  void onPanStart(DragStartInfo info) {
    // Allow aiming from anywhere on screen
    if (!_arrow.isFlying) {
      _isAiming = true;
      _dragStartPosition = info.eventPosition.widget;
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_isAiming && !_arrow.isFlying && _dragStartPosition != null) {
      final currentPosition = info.eventPosition.widget;

      // Calculate aim direction (from arrow start position to where user is dragging)
      final aimVector = currentPosition - _arrowStartPosition;
      final aimDistance = aimVector.length;

      // Only update if user has dragged away from arrow start (minimum distance)
      if (aimDistance > 20) {
        // Normalize aim direction
        final normalizedAim = aimVector.normalized();

        // Limit how far back you can pull
        final maxPullDistance = 200.0;
        final pullDistance = math.min(aimDistance, maxPullDistance);

        // Rotate arrow but keep it anchored at start position
        final aimAngle = math.atan2(normalizedAim.y, normalizedAim.x);
        _arrow.setAimPosition(_arrow.startPosition, aimAngle);
        _arrow.aimDirection = normalizedAim;
        _arrow.pullStrength = pullDistance / maxPullDistance;
      }
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    if (_isAiming) {
      _arrow.shoot();
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

  // Parameters for making the arrow follow the analytic curve exactly
  bool _followAnalytic = false;
  double _analyticSpeed = 0.0;
  double _analyticAngleDeg = 0.0;
  double _analyticTime = 0.0;
  forge2d.Vector2? _analyticStart;

  ArrowComponent({required this.startPosition});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Load sprite
    final sprite = await Sprite.load('arrow.png');
    spriteSize = sprite.originalSize * 0.2;

    // Create sprite component as child
    spriteComponent = SpriteComponent(
      sprite: sprite,
      size: spriteSize,
      // Center-right so that the physics body's position is near the arrow head.
      anchor: Anchor.centerRight,
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
      ..restitution = 0.1; // Slight bounce

    body.createFixture(fixtureDef);

    // Store reference to this component in body userData
    body.userData = this;

    // Initially, make body sleep (not affected by physics until shot)
    body.setAwake(false);

    return body;
  }

  void setAimPosition(Vector2 position, double angle) {
    // Convert Flame Vector2 to Forge2D Vector2
    final forge2dPosition = forge2d.Vector2(position.x, position.y);
    // When aiming, update body position and angle, keep it awake but with zero velocity
    body.setAwake(true);
    body.setTransform(forge2dPosition, angle);
    body.linearVelocity = forge2d.Vector2.zero();
    body.angularVelocity = 0.0;
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
      body.setAwake(true);
      body.linearVelocity = velocity;
    }
  }

  /// Shoots the arrow along an analytic projectile curve with the given speed
  /// and launch angle (in degrees), using the same coordinate convention as
  /// [ProjectilePathComponent].
  void shootAlongCurve({required double speed, required double angleDegrees}) {
    if (isFlying) return;

    isFlying = true;

    // Configure analytic-follow parameters so update() can drive the body.
    _followAnalytic = true;
    _analyticSpeed = speed;
    _analyticAngleDeg = angleDegrees;
    _analyticTime = 0.0;

    // _analyticStart stores the HEAD position for t = 0.
    // This should be the origin of our custom axes (screen center),
    // which is where the red curve starts.
    _analyticStart = forge2d.Vector2(game.size.x / 2, game.size.y / 2);

    // Turn off gravity for this body; we will apply the analytic motion manually
    body.gravityScale = forge2d.Vector2.zero();
    body.setAwake(true);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isFlying) {
      // If configured, move the arrow along the same analytic curve used
      // by [ProjectilePathComponent], so it visually follows the red path.
      if (_followAnalytic && _analyticStart != null) {
        _analyticTime += dt;

        final g = game.world.gravity.y.toDouble();
        final angleRad = -_analyticAngleDeg * math.pi / 180.0;

        final vx0 = _analyticSpeed * math.cos(angleRad);
        final vy0 = _analyticSpeed * math.sin(angleRad);

        // Analytic position/velocity of the ARROW HEAD.
        final headX = _analyticStart!.x + vx0 * _analyticTime;
        final headY =
            _analyticStart!.y +
            vy0 * _analyticTime +
            0.5 * g * _analyticTime * _analyticTime;

        final vx = vx0;
        final vy = vy0 + g * _analyticTime;

        // With anchor = centerRight, the physics body's position represents
        // (approximately) the arrow head, so we place the body directly on
        // the analytic head position.
        body.setTransform(forge2d.Vector2(headX, headY), math.atan2(vy, vx));
        body.linearVelocity = forge2d.Vector2(vx, vy);

        // Stop following after we come back to the original vertical level
        // (i.e. full arc is complete), similar to the red curve logic.
        if (_analyticTime > 0 && headY >= _analyticStart!.y) {
          _followAnalytic = false;
          body.gravityScale = forge2d.Vector2(
            1.0,
            1.0,
          ); // restore gravity if we want physics again
        }
      }

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
    body.setTransform(forge2dPosition, 0.0);
    body.linearVelocity = forge2d.Vector2.zero();
    body.angularVelocity = 0.0;
    body.setAwake(false);
  }

  // Collision detection - this will be called by Forge2D when collision occurs
  void onCollision(forge2d.Contact contact, Object other) {
    // Handle collision with other objects
    // For example, you could check if it's a target, obstacle, etc.
    print('Arrow collided with: $other');
  }
}
