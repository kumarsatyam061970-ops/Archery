import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' show SystemChrome, DeviceOrientation;

void main() {
  // Force landscape
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const TestArrowApp());
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

class TestArrowGame extends FlameGame with KeyboardEvents, PanDetector {
  // Single origin to control axes and spawn point
  Offset origin = const Offset(25, 350);
  double gravity = 60;
  double speed = 300;
  Vector2 aimDir = Vector2(1, 0); // updated from mouse

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
  }

  late StaticArrow staticArrow;

  void _spawnArrow() {
    final start = Vector2(origin.dx, origin.dy);
    final angleDeg = (math.atan2(aimDir.y, aimDir.x) * 180 / math.pi);

    add(
      ParabolaArrow(
        startPos: start,
        angleDeg: angleDeg,
        speed: speed,
        gravity: gravity,
        maxTime: 10.0,
      ),
    );

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
// 🎯 PARABOLA ARROW
// =======================
class ParabolaArrow extends SpriteComponent with HasGameRef<TestArrowGame> {
  ParabolaArrow({
    required this.startPos,
    required this.angleDeg,
    required this.speed,
    this.gravity = 9.8,
    this.maxTime = 10.0,
  }) : super(anchor: Anchor.center);

  final Vector2 startPos;
  final double angleDeg;
  final double speed;
  final double gravity;
  final double maxTime;

  late final Vector2 v0;
  double t = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await Sprite.load('arrow.png');
    // Preserve the image aspect ratio
    const baseWidth = 140.0;
    final aspect = sprite!.originalSize.y / sprite!.originalSize.x;
    size = Vector2(baseWidth, baseWidth * aspect);

    final angleRad = angleDeg * math.pi / 180;
    v0 = Vector2(math.cos(angleRad) * speed, math.sin(angleRad) * speed);
    position = startPos;
  }

  @override
  void update(double dt) {
    super.update(dt);
    t += 3 * dt;
    if (t > maxTime) {
      removeFromParent();
      return;
    }

    final x = startPos.x + v0.x * t;
    final y = startPos.y + v0.y * t + 0.5 * gravity * t * t;
    position = Vector2(x, y);

    final vx = v0.x;
    final vy = v0.y + gravity * t;
    if (vx * vx + vy * vy > 1e-6) {
      angle = math.atan2(vy, vx);
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
