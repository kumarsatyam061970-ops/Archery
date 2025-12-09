import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show SystemChrome, DeviceOrientation;
import 'package:forge2d/forge2d.dart' as forge2d;

void main() {
  // Force landscape
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const TestArrowApp());
}

/// ContactListener to detect collisions between arrows and the boy character
class ArrowContactListener extends ContactListener {
  @override
  void beginContact(Contact contact) {
    final fixtureA = contact.fixtureA;
    final fixtureB = contact.fixtureB;

    final bodyA = fixtureA.body.userData;
    final bodyB = fixtureB.body.userData;

    // Debug: print all contacts to see what's happening
    print(
      '🔍 Contact detected: bodyA=${bodyA.runtimeType}, bodyB=${bodyB.runtimeType}',
    );
    print(
      '   fixtureA.userData=${fixtureA.userData}, fixtureB.userData=${fixtureB.userData}',
    );

    // Check if one is an arrow and the other is the boy
    ParabolaArrow? arrow;
    BoyCharacter? boy;
    String? bodyPart;

    if (bodyA is ParabolaArrow && bodyB is BoyCharacter) {
      arrow = bodyA;
      boy = bodyB;
      // Check which body part was hit based on fixture userData
      if (fixtureB.userData is String) {
        bodyPart = fixtureB.userData as String;
      }
      print('✅ Arrow (A) hit Boy (B), body part: $bodyPart');
    } else if (bodyB is ParabolaArrow && bodyA is BoyCharacter) {
      arrow = bodyB;
      boy = bodyA;
      // Check which body part was hit based on fixture userData
      if (fixtureA.userData is String) {
        bodyPart = fixtureA.userData as String;
      }
      print('✅ Arrow (B) hit Boy (A), body part: $bodyPart');
    }

    if (arrow != null && boy != null) {
      print('🎯 Arrow hit boy! Body part: ${bodyPart ?? "unknown"}');
      if (bodyPart != null) {
        boy.onBodyPartHit(bodyPart, arrow);
      }
      // Remove the arrow after collision
      arrow.removeFromParent();
    }
  }

  @override
  void endContact(Contact contact) {
    // Called when contact ends (optional)
  }

  @override
  void preSolve(Contact contact, Manifold oldManifold) {
    // Called before collision resolution (optional)
  }

  @override
  void postSolve(Contact contact, ContactImpulse impulse) {
    // Called after collision resolution (optional)
  }
}

class TestArrowApp extends StatelessWidget {
  const TestArrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.pink[50],
        body: Center(child: GameWidget(game: TestArrowGame())),
      ),
    );
  }
}

class TestArrowGame extends Forge2DGame with KeyboardEvents, PanDetector {
  // Single origin to control axes and spawn point
  Offset origin = const Offset(25, 350);
  double gravity = 60;
  double speed = 300;
  Vector2 aimDir = Vector2(1, 0); // updated from mouse

  TestArrowGame()
    : super(
        gravity: forge2d.Vector2(0, 60),
        zoom: 1.0,
        contactListener: ArrowContactListener(),
      );

  @override
  Color backgroundColor() => Colors.pink[50]!;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(AxesComponent(origin: origin));
    add(Line330Component(origin: origin, length: 800));
    add(AimInput(onAim: _updateAim));
    // Add a static arrow at the origin, rotated to 330°
    staticArrow = StaticArrow(
      angleDeg: 330.0,
      initialPosition: Vector2(origin.dx, origin.dy),
    );
    await add(staticArrow);

    // Add boy character at a position to the right of origin
    final boyPosition = Vector2(origin.dx + 400, origin.dy);
    await add(BoyCharacter(position: boyPosition));
  }

  late StaticArrow staticArrow;

  void _spawnArrow() {
    final start = Vector2(origin.dx, origin.dy);
    final angleDeg = (math.atan2(aimDir.y, aimDir.x) * 180 / math.pi);

    add(ParabolaArrow(startPos: start, angleDeg: angleDeg, speed: speed));

    add(
      ParabolaPathVisualizer(
        startPos: start,
        angleDeg: angleDeg,
        speed: speed,
        gravity: gravity,
        maxTime: 10.0,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (staticArrow.isLoaded && aimDir.length2 > 1e-4) {
      staticArrow.angle = math.atan2(aimDir.y, aimDir.x);
    }
  }

  void _updateAim(Vector2 target) {
    final originVec = Vector2(origin.dx, origin.dy);
    final dir = target - originVec;
    if (dir.length2 > 1e-4) {
      // Compute angle in [-180, 180], clamp to [-90, 0] (i.e. 270..360 wrap)
      final angleDeg = math.atan2(dir.y, dir.x) * 180 / math.pi;
      final clampedDeg = angleDeg.clamp(-90.0, 0.0);
      final rad = clampedDeg * math.pi / 180;
      aimDir = Vector2(math.cos(rad), math.sin(rad));
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    _updateAim(info.eventPosition.widget);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _spawnArrow();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

// =======================
// 📐 AXES
// =======================
class AxesComponent extends Component {
  AxesComponent({required this.origin, this.axisLength = 1000});

  final Offset origin;
  final double axisLength;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paintX = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;
    final paintY = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    // Horizontal through origin
    canvas.drawLine(
      Offset(-axisLength, origin.dy),
      Offset(axisLength, origin.dy),
      paintX,
    );
    // Vertical through origin
    canvas.drawLine(
      Offset(origin.dx, origin.dy - axisLength),
      Offset(origin.dx, origin.dy + axisLength),
      paintY,
    );
  }
}

// =======================
// 🎯 PARABOLA ARROW (Physics-based)
// =======================
Sprite? _sharedArrowSprite;
Vector2? _sharedArrowSpriteSize;

class ParabolaArrow extends BodyComponent<TestArrowGame> {
  final Vector2 startPos;
  final double angleDeg;
  final double speed;

  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2(44, 8.8);

  ParabolaArrow({
    required this.startPos,
    required this.angleDeg,
    required this.speed,
  });

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
    final angleRad = angleDeg * math.pi / 180;
    final initialVelocity = Vector2(
      math.cos(angleRad) * speed,
      math.sin(angleRad) * speed,
    );

    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.dynamic,
      position: forge2d.Vector2(startPos.x, startPos.y),
      angle: angleRad,
      bullet: true,
      fixedRotation: true, // Prevent automatic physics rotation
    );

    final body = world.createBody(bodyDef);

    final shape = forge2d.PolygonShape()
      ..setAsBox(60, 10, forge2d.Vector2.zero(), 0.0);

    final fixtureDef = forge2d.FixtureDef(shape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.1
      ..isSensor = true; // Collision detection only, no physical response

    body.createFixture(fixtureDef);

    // Set userData so ContactListener can identify this as an arrow
    body.userData = this;

    body
      ..gravityScale =
          forge2d.Vector2(0, 1) // Enable gravity
      ..setAwake(true)
      ..setActive(true); // Ensure body is active for collision detection

    final mass = body.mass;
    final impulse = forge2d.Vector2(
      initialVelocity.x * mass,
      initialVelocity.y * mass,
    );

    body.applyLinearImpulse(impulse, point: body.worldCenter);

    return body;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final velocity = body.linearVelocity;
    if (velocity.length2 > 1e-4) {
      final angle = math.atan2(velocity.y, velocity.x);
      spriteComponent.angle = angle;
      // Update body angle so physics shape rotates too
      body.setTransform(body.position, angle);
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

/// A simple, non-physics arrow instance placed at an angle/position.
class StaticArrow extends SpriteComponent with HasGameRef<TestArrowGame> {
  StaticArrow({required this.angleDeg, required this.initialPosition})
    : super(anchor: Anchor.center);

  final double angleDeg;
  final Vector2 initialPosition;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await Sprite.load('arrow.png');
    // Preserve the image aspect ratio
    const baseWidth = 140.0;
    final aspect = sprite!.originalSize.y / sprite!.originalSize.x;
    size = Vector2(baseWidth, baseWidth * aspect);
    angle = angleDeg * math.pi / 180.0;
    position = initialPosition;
  }
}

/// Full-screen input catcher to update aim direction from mouse/touch/drag.
class AimInput extends PositionComponent
    with HasGameRef<TestArrowGame>, TapCallbacks {
  AimInput({required this.onAim});

  final void Function(Vector2) onAim;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = gameRef.size;
    position = Vector2.zero();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void onTapDown(TapDownEvent event) {
    onAim(event.localPosition);
  }
}

// =======================
// 🎨 PARABOLA PATH PREVIEW
// =======================
class ParabolaPathVisualizer extends Component with HasGameRef<TestArrowGame> {
  ParabolaPathVisualizer({
    required this.startPos,
    required this.angleDeg,
    required this.speed,
    this.gravity = 9.8,
    this.maxTime = 4.0,
    this.samples = 120,
  });

  final Vector2 startPos;
  final double angleDeg;
  final double speed;
  final double gravity;
  final double maxTime;
  final int samples;

  final List<Offset> points = [];

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final angleRad = angleDeg * math.pi / 180;
    final v0 = Vector2(math.cos(angleRad) * speed, math.sin(angleRad) * speed);

    for (int i = 0; i <= samples; i++) {
      final tt = maxTime * (i / samples);
      final x = startPos.x + v0.x * tt;
      final y = startPos.y + v0.y * tt + 0.5 * gravity * tt * tt;
      points.add(Offset(x, y));
      if (y > gameRef.size.y + 400) break;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (points.length < 2) return;
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

// =======================
// 🔴 ANGLE REFERENCE LINE
// =======================
class Line330Component extends Component {
  Line330Component({required this.origin, this.length = 600});

  final Offset origin;
  final double length;

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final angleRad = 330 * math.pi / 180;
    final end = origin.translate(
      math.cos(angleRad) * length,
      math.sin(angleRad) * length,
    );

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;

    canvas.drawLine(origin, end, paint);
  }
}

// =======================
// 👦 BOY CHARACTER WITH COLLIDERS
// =======================
class BoyCharacter extends BodyComponent<TestArrowGame> {
  final Vector2 position;
  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2.zero();

  // Store vertices for rendering
  List<forge2d.Vector2> headVertices = [];
  List<forge2d.Vector2> upperBodyVertices = [];
  List<forge2d.Vector2> legsVertices = [];

  BoyCharacter({required this.position});

  // Make colliders visible for debugging (set renderBody = true to see them)
  @override
  Paint get paint => Paint()
    ..color = Colors.blue.withOpacity(0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  @override
  bool get renderBody => false; // We'll render custom green lines instead

  @override
  Future<void> onLoad() async {
    // Load sprite FIRST before calling super.onLoad() so spriteSize is available for createBody()
    final sprite = await Sprite.load('boy.png');
    final originalSize = sprite.originalSize;

    // Set x size to 100 and calculate y based on aspect ratio
    const targetWidth = 100.0;
    final aspectRatio = originalSize.y / originalSize.x;
    spriteSize = Vector2(targetWidth, targetWidth * aspectRatio);

    // Now call super.onLoad() which will call createBody()
    await super.onLoad();

    spriteComponent = SpriteComponent(
      sprite: sprite,
      size: spriteSize, // x=100, y calculated from aspect ratio
      anchor: Anchor.center,
    );
    add(spriteComponent);
  }

  @override
  forge2d.Body createBody() {
    // Ensure spriteSize is valid (should be set in onLoad before super.onLoad())
    // Use fallback size if spriteSize is not yet set
    final effectiveWidth = spriteSize.x > 0 ? spriteSize.x : 100.0;
    final effectiveHeight = spriteSize.y > 0 ? spriteSize.y : 150.0;

    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.dynamic,
      position: forge2d.Vector2(position.x, position.y),
      angle: 0.0,
      fixedRotation: true,
    );

    final body = world.createBody(bodyDef);

    // Calculate proportional offsets based on sprite size
    final spriteWidth = effectiveWidth;
    final spriteHeight = effectiveHeight;

    // Head polygon - top portion of sprite (approximately top 30% of height)
    final headTop = -spriteHeight * 0.35; // Top of head
    final headBottom = -spriteHeight * 0.05; // Bottom of head
    final headWidth = spriteWidth * 0.35; // Width of head

    headVertices = [
      forge2d.Vector2(-headWidth * 0.9, headTop), // Top left
      forge2d.Vector2(headWidth * 0.9, headTop), // Top right
      forge2d.Vector2(headWidth, headTop + spriteHeight * 0.08), // Right upper
      forge2d.Vector2(
        headWidth * 0.95,
        headTop + spriteHeight * 0.15,
      ), // Right middle
      forge2d.Vector2(headWidth * 0.85, headBottom), // Right lower
      forge2d.Vector2(-headWidth * 0.85, headBottom), // Left lower
      forge2d.Vector2(
        -headWidth * 0.95,
        headTop + spriteHeight * 0.15,
      ), // Left middle
      forge2d.Vector2(-headWidth, headTop + spriteHeight * 0.08), // Left upper
    ];

    final headShape = forge2d.PolygonShape()..set(headVertices);

    final headFixture = forge2d.FixtureDef(headShape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.1
      ..isSensor = false;

    final headFixtureObj = body.createFixture(headFixture);
    headFixtureObj.userData = 'head';

    // Upper body polygon - middle portion (approximately 30-60% of height)
    final upperBodyTop = -spriteHeight * 0.05;
    final upperBodyBottom = spriteHeight * 0.25;
    final upperBodyWidth = spriteWidth * 0.4;

    upperBodyVertices = [
      forge2d.Vector2(-upperBodyWidth, upperBodyTop), // Top left (shoulder)
      forge2d.Vector2(upperBodyWidth, upperBodyTop), // Top right (shoulder)
      forge2d.Vector2(
        upperBodyWidth * 1.05,
        upperBodyBottom,
      ), // Bottom right (waist)
      forge2d.Vector2(
        -upperBodyWidth * 1.05,
        upperBodyBottom,
      ), // Bottom left (waist)
    ];

    final upperBodyShape = forge2d.PolygonShape()..set(upperBodyVertices);

    final upperBodyFixture = forge2d.FixtureDef(upperBodyShape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.1
      ..isSensor = false;

    final upperBodyFixtureObj = body.createFixture(upperBodyFixture);
    upperBodyFixtureObj.userData = 'upperBody';

    // Legs polygon - bottom portion (approximately bottom 40% of height)
    final legsTop = spriteHeight * 0.09;
    final legsBottom = spriteHeight * 0.40;
    final legsWidth = spriteWidth * 0.15;
    final footWidth = spriteWidth * 0.2;

    legsVertices = [
      forge2d.Vector2(-legsWidth, legsTop), // Top left
      forge2d.Vector2(legsWidth, legsTop), // Top right
      forge2d.Vector2(legsWidth * 1.1, legsBottom), // Bottom right
      forge2d.Vector2(
        footWidth,
        legsBottom + spriteHeight * 0.05,
      ), // Right foot outer
      forge2d.Vector2(
        footWidth * 0.5,
        legsBottom + spriteHeight * 0.05,
      ), // Right foot inner
      forge2d.Vector2(
        -footWidth * 0.5,
        legsBottom + spriteHeight * 0.05,
      ), // Left foot inner
      forge2d.Vector2(
        -footWidth,
        legsBottom + spriteHeight * 0.05,
      ), // Left foot outer
      forge2d.Vector2(-legsWidth * 1.1, legsBottom), // Bottom left
    ];

    final legsShape = forge2d.PolygonShape()..set(legsVertices);

    final legsFixture = forge2d.FixtureDef(legsShape)
      ..density = 1.0
      ..friction = 0.5
      ..restitution = 0.1
      ..isSensor = false;

    final legsFixtureObj = body.createFixture(legsFixture);
    legsFixtureObj.userData = 'legs';

    body.userData = this;

    // Set gravity to zero so the boy stays in place
    body.gravityScale = forge2d.Vector2.zero();
    // Keep body awake and active so it can detect collisions
    // Even though it's dynamic, with zero gravity and no forces, it will stay in place
    body
      ..setAwake(true)
      ..setActive(true); // Ensure body is active for collision detection

    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw green lines for each collider
    final greenPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw head collider in green
    if (headVertices.isNotEmpty) {
      _drawPolygon(canvas, headVertices, greenPaint);
    }

    // Draw upper body collider in green
    if (upperBodyVertices.isNotEmpty) {
      _drawPolygon(canvas, upperBodyVertices, greenPaint);
    }

    // Draw legs collider in green
    if (legsVertices.isNotEmpty) {
      _drawPolygon(canvas, legsVertices, greenPaint);
    }
  }

  void _drawPolygon(
    Canvas canvas,
    List<forge2d.Vector2> vertices,
    Paint paint,
  ) {
    if (vertices.isEmpty) return;

    final path = Path();

    // Convert Forge2D vertices to Flutter Offsets
    // Note: Canvas is already transformed by BodyComponent's renderTree,
    // so vertices are in local space (relative to body center)
    final offsets = vertices
        .map((v) => Offset(v.x.toDouble(), v.y.toDouble()))
        .toList();

    // Draw the polygon
    path.moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      path.lineTo(offsets[i].dx, offsets[i].dy);
    }
    path.close(); // Close the polygon

    canvas.drawPath(path, paint);
  }

  void onBodyPartHit(String bodyPart, Object other) {
    print('Body part hit: $bodyPart');
    // Handle different body part hits
    switch (bodyPart) {
      case 'head':
        print('Critical hit on head!');
        break;
      case 'upperBody':
        print('Hit on upper body!');
        break;
      case 'legs':
        print('Hit on legs!');
        break;
    }
  }
}
