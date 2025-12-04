import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge2d/forge2d.dart' as forge2d;

double _degFromRadians(double radians) {
  final deg = radians * 180 / math.pi;
  // Apply custom convention: left=0, down=90, right=180, up=270
  // Adjust so left = 0° (subtract 135.42° offset from sprite + mirroring)
  return ((deg - 135.42) % 360 + 360) % 360;
}

double _degFromVector(Vector2 vector) =>
    _degFromRadians(math.atan2(vector.y, vector.x));

String _fmtDeg(double degrees) => degrees.toStringAsFixed(2);

String _fmtPos(Vector2 position) =>
    '(${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)})';

void main() {
  runApp(const MaterialApp(home: GameScreen()));
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final ArcheryGame game;

  @override
  void initState() {
    super.initState();
    game = ArcheryGame();
  }

  void _setArrowAngle(double degrees) {
    game.setArrowAngleDegrees(degrees);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameWidget(game: game),
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _setArrowAngle(0),
                  child: const Text('0°'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _setArrowAngle(90),
                  child: const Text('90°'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _setArrowAngle(180),
                  child: const Text('180°'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _setArrowAngle(270),
                  child: const Text('270°'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ArcheryGame extends Forge2DGame with KeyboardEvents {
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

    // Origin at center of screen for our custom axes
    final center = size / 2;

    // Arrow for aiming sits at the origin (0, 0) of our custom axes.
    const launchAngleDeg = 30.0;
    _arrowStartPosition = center;

    _arrow = ArrowComponent(startPosition: _arrowStartPosition);
    await add(_arrow);
    await add(ArrowAxesOverlay(arrow: _arrow));

    // Immediately shoot the arrow so that its HEAD follows the red curve.
    // _arrow.shootAlongCurve(speed: 150.0, angleDegrees: launchAngleDeg);
  }

  // @override
  // void onPanStart(DragStartInfo info) {
  //   // Allow aiming from anywhere on screen
  //   if (!_arrow.isFlying) {
  //     _isAiming = true;
  //     _dragStartPosition = info.eventPosition.widget;
  //     _aimArrowAt(info.eventPosition.widget);
  //   }
  // }

  // @override
  // void onPanUpdate(DragUpdateInfo info) {
  //   if (_isAiming && !_arrow.isFlying && _dragStartPosition != null) {
  //     final currentPosition = info.eventPosition.widget;

  //     _aimArrowAt(currentPosition);

  //     // Calculate pull strength based on distance from start position
  //     final aimVector = currentPosition - _arrow.startPosition;
  //     final aimDistance = aimVector.length;

  //     // Update aim direction even for small drags so the firing direction
  //     // always matches the visual arrow orientation.
  //     if (aimDistance > 0) {
  //       _arrow.aimDirection = aimVector.normalized();
  //     }

  //     // Only update if user has dragged away from arrow start (minimum distance)
  //     if (aimDistance > 20) {
  //       // Limit how far back you can pull
  //       final maxPullDistance = 200.0;
  //       final pullDistance = math.min(aimDistance, maxPullDistance);

  //       _arrow.pullStrength = pullDistance / maxPullDistance;
  //     }
  //   }
  // }

  // @override
  // void onPanEnd(DragEndInfo info) {
  //   if (_isAiming) {
  //     // _arrow.shoot();
  //     _isAiming = false;
  //     _dragStartPosition = null;
  //   }
  // }

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

  // @override
  // void onMouseMove(PointerHoverInfo info) {
  //   _aimArrowAt(info.eventPosition.widget);
  // }

  void setArrowAngleDegrees(double desiredDegrees) {
    // Convert from user's convention (left=0, down=90, right=180, up=270)
    // to sprite radians. Add 45.42° offset (135.42 - 90) to align properly.
    final spriteRadians = (desiredDegrees + 45.42) * math.pi / 180;
    _arrow.setAimPosition(_arrow.startPosition, spriteRadians);
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
    print(
      'Instantiated projectile angle: ${_fmtDeg(_degFromVector(velocity))}°',
    );

    await add(
      ArrowPathComponent(
        startPosition: spawnPosition.clone(),
        initialVelocity: velocity.clone(),
        gravity: world.gravity.y,
      ),
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

/// Draws a red parabolic projectile path for a given initial angle and speed.
Sprite? _sharedArrowSprite;
Vector2? _sharedArrowSpriteSize;

class ArrowComponent extends BodyComponent<ArcheryGame>
    with HasGameRef<ArcheryGame> {
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
    print(
      'Aim arrow pos=${_fmtPos(position)} '
      'angle=${_fmtDeg(_degFromRadians(angle))}°',
    );
  }

  void shoot() {
    if (pullStrength > 0 && !isFlying) {
      isFlying = true;

      // Calculate initial velocity based on aim direction and pull strength
      final speed =
          baseSpeed *
          (0.5 + pullStrength * 1.5); // Speed range: 0.5x to 2x base
      final desiredVelocity = forge2d.Vector2(
        aimDirection.x * speed,
        aimDirection.y * speed,
      );

      final arrowAngleDeg = _degFromRadians(spriteComponent.angle);
      final aimDirDeg = _degFromVector(aimDirection);
      print(
        'Arrow sprite angle: ${_fmtDeg(arrowAngleDeg)}°, aim dir: ${_fmtDeg(aimDirDeg)}°',
      );

      // Apply an impulse that yields the desired velocity; Box2D gravity creates the arc
      body
        ..gravityScale = forge2d.Vector2(1.0, 1.0)
        ..setAwake(true);

      final mass = body.mass;
      final impulse = forge2d.Vector2(
        desiredVelocity.x * mass,
        desiredVelocity.y * mass,
      );
      final impulseAngleDeg = _degFromVector(impulse);
      print('Impulse angle: ${_fmtDeg(impulseAngleDeg)}°');
      body.applyLinearImpulse(impulse, point: body.worldCenter);
      print('Arrow launched from ${_fmtPos(body.position)}');

      // Spawn a temporary visual trajectory path for the fired arrow
      gameRef.add(
        ArrowPathComponent(
          startPosition: Vector2(body.position.x, body.position.y),
          initialVelocity: Vector2(desiredVelocity.x, desiredVelocity.y),
          gravity: gameRef.world.gravity.y,
        ),
      );
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
        print(
          'Aim arrow traveling pos=${_fmtPos(body.position)} '
          'angle=${_fmtDeg(_degFromRadians(spriteComponent.angle))}°',
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

class ArrowAxesOverlay extends Component with HasGameRef<ArcheryGame> {
  final ArrowComponent arrow;
  final double axisLength;
  final Paint xPaint;
  final Paint yPaint;

  ArrowAxesOverlay({
    required this.arrow,
    this.axisLength = 80,
  })  : xPaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 2,
        yPaint = Paint()
          ..color = Colors.green
          ..strokeWidth = 2,
        super(priority: 1000);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final pos = arrow.body.position;
    final center = Offset(pos.x, pos.y);

    // X-axis line
    canvas.drawLine(
      center.translate(-axisLength, 0),
      center.translate(axisLength, 0),
      xPaint,
    );

    // Y-axis line
    canvas.drawLine(
      center.translate(0, -axisLength),
      center.translate(0, axisLength),
      yPaint,
    );

    final angleDeg = _fmtDeg(_degFromRadians(arrow.spriteComponent.angle));
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Angle: $angleDeg°',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = center.translate(10, -20);
    textPainter.paint(canvas, textOffset);
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
      ..setAwake(true);

    final mass = body.mass;
    final impulse = forge2d.Vector2(
      initialVelocity.x * mass,
      initialVelocity.y * mass,
    );
    print(
      'Projectile impulse angle: ${(math.atan2(impulse.y, impulse.x) * 180 / math.pi).toStringAsFixed(2)}°',
    );
    body.applyLinearImpulse(impulse, point: body.worldCenter);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final velocity = body.linearVelocity;
    if (velocity.length2 > 1e-4) {
      spriteComponent.angle = math.atan2(velocity.y, velocity.x);
      print(
        'Projectile traveling pos=${_fmtPos(body.position)} '
        'angle=${_fmtDeg(_degFromRadians(spriteComponent.angle))}°',
      );
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

class ArrowPathComponent extends Component with HasGameRef<ArcheryGame> {
  final Vector2 startPosition;
  final Vector2 initialVelocity;
  final double gravity;
  final List<Offset> _points = [];
  final double _lifetime = 2.0;
  double _age = 0.0;

  ArrowPathComponent({
    required this.startPosition,
    required this.initialVelocity,
    required this.gravity,
  });

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _generatePoints();
  }

  void _generatePoints() {
    _points.clear();
    final vx = initialVelocity.x;
    final vy = initialVelocity.y;
    final dt = 0.02;
    final maxTime = 5.0;
    for (double t = 0.0; t <= maxTime; t += dt) {
      final x = startPosition.x + vx * t;
      final y = startPosition.y + vy * t + 0.5 * gravity * t * t;
      _points.add(Offset(x, y));
      if (y > gameRef.size.y + 200) {
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

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _lifetime) {
      removeFromParent();
    }
  }
}

