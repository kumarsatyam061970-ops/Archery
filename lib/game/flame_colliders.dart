import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:forge2d/forge2d.dart' as forge2d;
import 'archery_game.dart' show ArcheryGame;

/// Configuration for body part vertices
class VertexConfig {
  final List<Vector2> headVertices;
  final List<Vector2> upperBodyVertices;
  final List<Vector2> legsVertices;

  VertexConfig({
    required this.headVertices,
    required this.upperBodyVertices,
    required this.legsVertices,
  });

  /// Default configuration (can be replaced with custom vertices)
  factory VertexConfig.defaultConfig() {
    return VertexConfig(
      headVertices: [
        Vector2(-35, -52.5), // Top left
        Vector2(35, -52.5), // Top right
        Vector2(30, -7.5), // Bottom right
        Vector2(-30, -7.5), // Bottom left
        // Reduced from 8 to 4 vertices (half) for simpler circular shape
      ],
      upperBodyVertices: [
        Vector2(-40, -7.5), // Top left (shoulder)
        Vector2(40, -7.5), // Top right (shoulder)
        Vector2(42, 37.5), // Bottom right (waist)
        Vector2(-42, 37.5), // Bottom left (waist)
      ],
      legsVertices: [
        Vector2(-35, 37.5), // Top left (waist)
        Vector2(35, 37.5), // Top right (waist)
        Vector2(35, 60), // Right upper leg (combined upper leg and knee)
        Vector2(25, 95), // Right lower leg/foot (combined lower leg and foot)
        Vector2(-25, 95), // Left lower leg/foot (combined lower leg and foot)
        Vector2(-35, 60), // Left upper leg (combined upper leg and knee)
        // Note: Forge2D has a max of 8 vertices per polygon, so we reduced from 10 to 6
      ],
    );
  }
}

/// Boy character with polygon colliders using Forge2D
class BoyCharacterWithColliders extends BodyComponent<ArcheryGame> {
  final Vector2 initialPosition;
  final VertexConfig vertexConfig;
  late SpriteComponent spriteComponent;
  Vector2 spriteSize = Vector2.zero();

  // Store vertices for rendering (in Forge2D format)
  List<forge2d.Vector2> headVertices = [];
  List<forge2d.Vector2> upperBodyVertices = [];
  List<forge2d.Vector2> legsVertices = [];

  // Edit mode
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;
  VertexEditorComponent? _vertexEditor;

  BoyCharacterWithColliders({
    required this.initialPosition,
    required this.vertexConfig,
  });

  // Make colliders visible for debugging
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

  void setEditMode(bool enabled) {
    _isEditMode = enabled;
    print('🎨 Edit mode set to: $_isEditMode');

    if (_isEditMode) {
      // Add vertex editor for all body parts
      if (_vertexEditor == null) {
        _vertexEditor = VertexEditorComponent(boyCharacter: this);
        add(_vertexEditor!);
        print('✅ Vertex editor added');
      } else {
        print('⚠️ Vertex editor already exists');
      }
    } else {
      // Remove vertex editor
      _vertexEditor?.removeFromParent();
      _vertexEditor = null;
      print('❌ Vertex editor removed');
    }
  }

  void printVertexConfig() {
    print('\n═══════════════════════════════════════════════════════');
    print('📐 VERTEX CONFIGURATION');
    print('═══════════════════════════════════════════════════════');
    print('\n// Head vertices:');
    print('headVertices: [');
    for (final v in vertexConfig.headVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('\n// Upper body vertices:');
    print('upperBodyVertices: [');
    for (final v in vertexConfig.upperBodyVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('\n// Legs vertices:');
    print('legsVertices: [');
    for (final v in vertexConfig.legsVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('═══════════════════════════════════════════════════════\n');
  }

  List<Vector2> getCurrentVertices(String bodyPart) {
    switch (bodyPart) {
      case 'head':
        return vertexConfig.headVertices;
      case 'upperBody':
        return vertexConfig.upperBodyVertices;
      case 'legs':
        return vertexConfig.legsVertices;
      default:
        return [];
    }
  }

  void updateVertex(String bodyPart, int index, Vector2 newPosition) {
    switch (bodyPart) {
      case 'head':
        if (index < vertexConfig.headVertices.length) {
          vertexConfig.headVertices[index] = newPosition;
          headVertices[index] = forge2d.Vector2(newPosition.x, newPosition.y);
          // Recreate body to update physics shape
          _recreateBody();
        }
        break;
      case 'upperBody':
        if (index < vertexConfig.upperBodyVertices.length) {
          vertexConfig.upperBodyVertices[index] = newPosition;
          upperBodyVertices[index] = forge2d.Vector2(
            newPosition.x,
            newPosition.y,
          );
          _recreateBody();
        }
        break;
      case 'legs':
        if (index < vertexConfig.legsVertices.length) {
          vertexConfig.legsVertices[index] = newPosition;
          legsVertices[index] = forge2d.Vector2(newPosition.x, newPosition.y);
          _recreateBody();
        }
        break;
    }
  }

  void _recreateBody() {
    // Remove all fixtures
    for (final fixture in body.fixtures.toList()) {
      body.destroyFixture(fixture);
    }

    // Recreate fixtures with updated vertices
    if (headVertices.length >= 3) {
      final headShape = forge2d.PolygonShape()..set(headVertices);
      final headFixture = forge2d.FixtureDef(headShape)
        ..density = 1.0
        ..friction = 0.3
        ..restitution = 0.1
        ..isSensor = false;
      final headFixtureObj = body.createFixture(headFixture);
      headFixtureObj.userData = 'head';
    }

    if (upperBodyVertices.length >= 3) {
      final upperBodyShape = forge2d.PolygonShape()..set(upperBodyVertices);
      final upperBodyFixture = forge2d.FixtureDef(upperBodyShape)
        ..density = 1.0
        ..friction = 0.3
        ..restitution = 0.1
        ..isSensor = false;
      final upperBodyFixtureObj = body.createFixture(upperBodyFixture);
      upperBodyFixtureObj.userData = 'upperBody';
    }

    if (legsVertices.length >= 3) {
      final legsShape = forge2d.PolygonShape()..set(legsVertices);
      final legsFixture = forge2d.FixtureDef(legsShape)
        ..density = 1.0
        ..friction = 0.5
        ..restitution = 0.1
        ..isSensor = false;
      final legsFixtureObj = body.createFixture(legsFixture);
      legsFixtureObj.userData = 'legs';
    }
  }

  void handlePanStart(DragStartInfo info) {
    if (_vertexEditor == null) return;

    final worldPos = info.eventPosition.widget;
    final vertices = _vertexEditor!.getVertices();

    // Find the closest vertex
    DraggableVertex? closestVertex;
    double minDistance = 50.0; // Selection threshold

    for (final vertex in vertices) {
      // Get vertex's absolute world position
      final vertexWorldPos = position + vertex.position;
      final distance = (worldPos - vertexWorldPos).length;

      if (distance < minDistance) {
        minDistance = distance;
        closestVertex = vertex;
      }
    }

    if (closestVertex != null) {
      closestVertex.startDragging();
      print(
        '🎯 Started dragging ${closestVertex.bodyPart}[${closestVertex.index}]',
      );
    }
  }

  void handlePanUpdate(DragUpdateInfo info) {
    if (_vertexEditor == null) return;

    final worldPos = info.eventPosition.widget;
    final vertices = _vertexEditor!.getVertices();

    for (final vertex in vertices) {
      if (vertex.isDragging) {
        // Pass world position to vertex, let it handle conversion
        vertex.updatePosition(worldPos);
        break;
      }
    }
  }

  void handlePanEnd(DragEndInfo info) {
    if (_vertexEditor == null) return;
    final vertices = _vertexEditor!.getVertices();
    for (final vertex in vertices) {
      vertex.stopDragging();
    }
  }

  @override
  forge2d.Body createBody() {
    final bodyDef = forge2d.BodyDef(
      type: forge2d.BodyType.dynamic,
      position: forge2d.Vector2(initialPosition.x, initialPosition.y),
      angle: 0.0,
      fixedRotation: true,
    );

    final body = world.createBody(bodyDef);

    // Convert VertexConfig to Forge2D vectors
    headVertices = vertexConfig.headVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();
    upperBodyVertices = vertexConfig.upperBodyVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();
    legsVertices = vertexConfig.legsVertices
        .map((v) => forge2d.Vector2(v.x, v.y))
        .toList();

    // Create head fixture
    if (headVertices.length >= 3) {
      final headShape = forge2d.PolygonShape()..set(headVertices);
      final headFixture = forge2d.FixtureDef(headShape)
        ..density = 1.0
        ..friction = 0.3
        ..restitution = 0.1
        ..isSensor = false;
      final headFixtureObj = body.createFixture(headFixture);
      headFixtureObj.userData = 'head';
    }

    // Create upper body fixture
    if (upperBodyVertices.length >= 3) {
      final upperBodyShape = forge2d.PolygonShape()..set(upperBodyVertices);
      final upperBodyFixture = forge2d.FixtureDef(upperBodyShape)
        ..density = 1.0
        ..friction = 0.3
        ..restitution = 0.1
        ..isSensor = false;
      final upperBodyFixtureObj = body.createFixture(upperBodyFixture);
      upperBodyFixtureObj.userData = 'upperBody';
    }

    // Create legs fixture
    if (legsVertices.length >= 3) {
      final legsShape = forge2d.PolygonShape()..set(legsVertices);
      final legsFixture = forge2d.FixtureDef(legsShape)
        ..density = 1.0
        ..friction = 0.5
        ..restitution = 0.1
        ..isSensor = false;
      final legsFixtureObj = body.createFixture(legsFixture);
      legsFixtureObj.userData = 'legs';
    }

    body.userData = this;

    // Set gravity to zero so the boy stays in place
    body.gravityScale = forge2d.Vector2.zero();
    body
      ..setAwake(true)
      ..setActive(true);

    return body;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw green lines for each collider
    final greenPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    // Draw head collider (only if vertices exist)
    if (headVertices.isNotEmpty) {
      _drawPolygon(canvas, headVertices, greenPaint);
    }

    // Draw upper body collider (only if vertices exist)
    if (upperBodyVertices.isNotEmpty) {
      _drawPolygon(canvas, upperBodyVertices, greenPaint);
    }

    // Draw legs collider (only if vertices exist)
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

    // Debug: Draw vertex points as small circles
    final vertexPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    for (final vertex in vertices) {
      canvas.drawCircle(
        Offset(vertex.x.toDouble(), vertex.y.toDouble()),
        3,
        vertexPaint,
      );
    }
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
    // Note: Server is authoritative for collision detection
    // This is just for client-side visual feedback
  }
}

/// Interactive vertex editor component
class VertexEditorComponent extends PositionComponent
    with HasGameRef<ArcheryGame>, TapCallbacks {
  final BoyCharacterWithColliders boyCharacter;
  List<DraggableVertex> vertices = [];

  VertexEditorComponent({required this.boyCharacter})
    : super(
        position:
            Vector2.zero(), // Position relative to boy character (its parent)
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _updateVertices();
  }

  void _updateVertices() {
    // Remove old vertices
    for (final vertex in vertices) {
      vertex.removeFromParent();
    }
    vertices.clear();

    // Create draggable vertices for all body parts
    // Head vertices (red/orange)
    final headVertices = boyCharacter.getCurrentVertices('head');
    print('📐 Creating ${headVertices.length} head vertices');
    for (int i = 0; i < headVertices.length; i++) {
      final vertex = DraggableVertex(
        index: i,
        initialPosition: headVertices[i],
        bodyPart: 'head',
        boyCharacter: boyCharacter,
        onUpdate: () {
          // Vertex updated - collider will be updated automatically
        },
      );
      vertices.add(vertex);
      add(vertex);
    }

    // Upper body vertices (yellow/green)
    final upperBodyVertices = boyCharacter.getCurrentVertices('upperBody');
    print('📐 Creating ${upperBodyVertices.length} upper body vertices');
    for (int i = 0; i < upperBodyVertices.length; i++) {
      final vertex = DraggableVertex(
        index: i,
        initialPosition: upperBodyVertices[i],
        bodyPart: 'upperBody',
        boyCharacter: boyCharacter,
        onUpdate: () {
          // Vertex updated - collider will be updated automatically
        },
      );
      vertices.add(vertex);
      add(vertex);
    }

    // Legs vertices (blue/cyan)
    final legsVertices = boyCharacter.getCurrentVertices('legs');
    print('📐 Creating ${legsVertices.length} legs vertices');
    for (int i = 0; i < legsVertices.length; i++) {
      final vertex = DraggableVertex(
        index: i,
        initialPosition: legsVertices[i],
        bodyPart: 'legs',
        boyCharacter: boyCharacter,
        onUpdate: () {
          // Vertex updated - collider will be updated automatically
        },
      );
      vertices.add(vertex);
      add(vertex);
    }

    print('✅ Total vertices created: ${vertices.length}');
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw instructions
    final textPainter = TextPainter(
      text: const TextSpan(
        text:
            'Editing all body parts (Click & drag vertices, Press P to print config)\n'
            'Head: Red | Upper Body: Yellow | Legs: Blue',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, const Offset(10, 10));
  }

  List<DraggableVertex> getVertices() => vertices;
}

/// Draggable vertex point
class DraggableVertex extends PositionComponent
    with HasGameRef<ArcheryGame>, TapCallbacks {
  final int index;
  final String bodyPart;
  final BoyCharacterWithColliders boyCharacter;
  final VoidCallback onUpdate;
  bool _isDragging = false;

  bool get isDragging => _isDragging;

  void startDragging() {
    _isDragging = true;
  }

  DraggableVertex({
    required this.index,
    required Vector2 initialPosition,
    required this.bodyPart,
    required this.boyCharacter,
    required this.onUpdate,
  }) : super(
         position: initialPosition,
         size: Vector2(20, 20),
         anchor: Anchor.center,
       );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
  }

  Color get _vertexColor {
    // Different colors for each body part
    switch (bodyPart) {
      case 'head':
        return _isDragging ? Colors.red : Colors.orange;
      case 'upperBody':
        return _isDragging ? Colors.green : Colors.yellow;
      case 'legs':
        return _isDragging ? Colors.cyan : Colors.blue;
      default:
        return Colors.yellow;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw vertex circle with body part-specific color
    final paint = Paint()
      ..color = _vertexColor
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset.zero, 8, paint);
    canvas.drawCircle(Offset.zero, 8, borderPaint);

    // Draw index number and body part label
    final label = '$bodyPart[$index]';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2 - 12),
    );
  }

  @override
  bool onTapDown(TapDownEvent event) {
    _isDragging = true;
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
  }

  void updatePosition(Vector2 mouseWorldPos) {
    if (_isDragging) {
      // Convert mouse world position to boy's local space
      final boyWorldPos = boyCharacter.position;
      final localPos = mouseWorldPos - boyWorldPos;

      position = localPos;
      boyCharacter.updateVertex(bodyPart, index, localPos);
    }
  }

  void stopDragging() {
    if (_isDragging) {
      _isDragging = false;
      onUpdate();
    }
  }
}
