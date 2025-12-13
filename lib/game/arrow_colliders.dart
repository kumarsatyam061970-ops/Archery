import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:forge2d/forge2d.dart' as forge2d;
import 'archery_game.dart' show ArcheryGame;

/// Configuration for arrow body part vertices (relative to arrow center)
class ArrowVertexConfig {
  final List<Vector2> headVertices;
  final List<Vector2> bodyVertices;
  final List<Vector2> tailVertices;

  ArrowVertexConfig({
    required this.headVertices,
    required this.bodyVertices,
    required this.tailVertices,
  });

  /// Default configuration for arrow colliders
  /// Arrow points in positive X direction (to the right)
  /// Arrow size is approximately 44x8.8 (scaled to 0.2)
  factory ArrowVertexConfig.defaultConfig() {
    // Use actual sprite size for better visibility
    final arrowLength = 44.0 * 0.2; // 8.8
    final arrowWidth = 8.8 * 0.2; // ~1.76
    final headLength = arrowLength * 0.3; // ~2.64 (front 30%)
    final tailLength = arrowLength * 0.3; // ~2.64 (back 30%)
    
    print('📐 Arrow collider config: length=$arrowLength, width=$arrowWidth');

    return ArrowVertexConfig(
      // Head (arrow tip) - triangular shape at the front
      headVertices: [
        Vector2(arrowLength / 2, 0), // Tip (rightmost point)
        Vector2(arrowLength / 2 - headLength, -arrowWidth / 2), // Top left
        Vector2(arrowLength / 2 - headLength, arrowWidth / 2), // Bottom left
      ],
      // Body (middle section) - rectangular shape
      bodyVertices: [
        Vector2(arrowLength / 2 - headLength, -arrowWidth / 2), // Top left
        Vector2(-arrowLength / 2 + tailLength, -arrowWidth / 2), // Top right
        Vector2(-arrowLength / 2 + tailLength, arrowWidth / 2), // Bottom right
        Vector2(arrowLength / 2 - headLength, arrowWidth / 2), // Bottom left
      ],
      // Tail (fletching) - wider at the back
      tailVertices: [
        Vector2(-arrowLength / 2 + tailLength, -arrowWidth / 2), // Top left
        Vector2(-arrowLength / 2, -arrowWidth), // Top right (wider)
        Vector2(-arrowLength / 2, arrowWidth), // Bottom right (wider)
        Vector2(-arrowLength / 2 + tailLength, arrowWidth / 2), // Bottom left
      ],
    );
  }
}

/// Arrow component with Forge2D polygon colliders for head, body, and tail
/// The colliders rotate and move with the arrow as it travels
class ArrowWithColliders extends BodyComponent<ArcheryGame> {
  final Vector2 initialPosition;
  final double initialAngleRad;
  final ArrowVertexConfig vertexConfig;
  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2(44, 8.8);

  // Store vertices for rendering (in Forge2D format)
  List<forge2d.Vector2> headVertices = [];
  List<forge2d.Vector2> bodyVertices = [];
  List<forge2d.Vector2> tailVertices = [];

  // Physics properties (for manual position updates)
  Vector2 currentPosition;
  double currentAngleRad;

  ArrowWithColliders({
    required this.initialPosition,
    required this.initialAngleRad,
    required this.vertexConfig,
  })  : currentPosition = initialPosition,
        currentAngleRad = initialAngleRad;

  @override
  Paint get paint => Paint()
    ..color = Colors.blue.withOpacity(0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  @override
  bool get renderBody => false; // We'll render custom lines instead

  @override
  Future<void> onLoad() async {
    // Load sprite FIRST before calling super.onLoad()
    final sprite = await Sprite.load('arrow.png');
    final originalSize = sprite.originalSize;
    spriteSize = originalSize * 0.2;

    print('🏹 [ARROW_COLLIDERS] Loading arrow with size: $spriteSize');

    // Now call super.onLoad() which will call createBody()
    await super.onLoad();

    spriteComponent = SpriteComponent(
      sprite: sprite,
      size: spriteSize,
      anchor: Anchor.center,
      angle: initialAngleRad,
    );
    add(spriteComponent);

    print('🏹 [ARROW_COLLIDERS] Arrow loaded. Head vertices: ${headVertices.length}, Body: ${bodyVertices.length}, Tail: ${tailVertices.length}');
  }

  /// Update arrow position and rotation (call this from parent component)
  void updatePositionAndAngle(Vector2 newPosition, double newAngleRad) {
    currentPosition = newPosition;
    currentAngleRad = newAngleRad;

    // Update Forge2D body position and angle
    body.setTransform(
      forge2d.Vector2(newPosition.x, newPosition.y),
      newAngleRad,
    );

    // Update sprite angle
    if (spriteComponent.isMounted) {
      spriteComponent.angle = newAngleRad;
    }
  }

  @override
  forge2d.Body createBody() {
    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.kinematic, // Kinematic so we control it manually
      position: forge2d.Vector2(initialPosition.x, initialPosition.y),
      angle: initialAngleRad,
      fixedRotation: false, // Allow rotation
    );

    final body = world.createBody(bodyDef);

    // Convert VertexConfig to Forge2D vectors
    headVertices = vertexConfig.headVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();
    bodyVertices = vertexConfig.bodyVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();
    tailVertices = vertexConfig.tailVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();

    // Create head fixture
    if (headVertices.length >= 3) {
      final headShape = forge2d.PolygonShape()..set(headVertices);
      final headFixture = forge2d.FixtureDef(headShape)
        ..density = 0.1
        ..friction = 0.1
        ..restitution = 0.0
        ..isSensor = true; // Sensor so it doesn't affect physics
      final headFixtureObj = body.createFixture(headFixture);
      headFixtureObj.userData = 'head';
    }

    // Create body fixture
    if (bodyVertices.length >= 3) {
      final bodyShape = forge2d.PolygonShape()..set(bodyVertices);
      final bodyFixture = forge2d.FixtureDef(bodyShape)
        ..density = 0.1
        ..friction = 0.1
        ..restitution = 0.0
        ..isSensor = true; // Sensor so it doesn't affect physics
      final bodyFixtureObj = body.createFixture(bodyFixture);
      bodyFixtureObj.userData = 'body';
    }

    // Create tail fixture
    if (tailVertices.length >= 3) {
      final tailShape = forge2d.PolygonShape()..set(tailVertices);
      final tailFixture = forge2d.FixtureDef(tailShape)
        ..density = 0.1
        ..friction = 0.1
        ..restitution = 0.0
        ..isSensor = true; // Sensor so it doesn't affect physics
      final tailFixtureObj = body.createFixture(tailFixture);
      tailFixtureObj.userData = 'tail';
    }

    body.userData = this;

    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw colored lines for each collider (for visual debugging)
    // Increased stroke width for better visibility
    final headPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final bodyPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final tailPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Draw head collider (red)
    if (headVertices.isNotEmpty) {
      _drawPolygon(canvas, headVertices, headPaint);
      // Debug: Draw vertex points
      final vertexPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      for (final vertex in headVertices) {
        canvas.drawCircle(
          Offset(vertex.x.toDouble(), vertex.y.toDouble()),
          2,
          vertexPaint,
        );
      }
    }

    // Draw body collider (blue)
    if (bodyVertices.isNotEmpty) {
      _drawPolygon(canvas, bodyVertices, bodyPaint);
      // Debug: Draw vertex points
      final vertexPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;
      for (final vertex in bodyVertices) {
        canvas.drawCircle(
          Offset(vertex.x.toDouble(), vertex.y.toDouble()),
          2,
          vertexPaint,
        );
      }
    }

    // Draw tail collider (green)
    if (tailVertices.isNotEmpty) {
      _drawPolygon(canvas, tailVertices, tailPaint);
      // Debug: Draw vertex points
      final vertexPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;
      for (final vertex in tailVertices) {
        canvas.drawCircle(
          Offset(vertex.x.toDouble(), vertex.y.toDouble()),
          2,
          vertexPaint,
        );
      }
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
    // Canvas is already transformed by BodyComponent's renderTree,
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

  /// Get which body part was hit (for collision detection)
  String? getHitBodyPart(forge2d.Fixture fixture) {
    if (fixture.userData is String) {
      return fixture.userData as String;
    }
    return null;
  }
}

