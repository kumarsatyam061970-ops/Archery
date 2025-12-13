import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'archery_game.dart' show ArcheryGame;

/// Configuration for arrow body part vertices
class ArrowVertexConfig {
  final List<Vector2> headVertices;
  final List<Vector2> bodyVertices;
  final List<Vector2> tailVertices;

  ArrowVertexConfig({
    required this.headVertices,
    required this.bodyVertices,
    required this.tailVertices,
  });

  /// Default configuration
  factory ArrowVertexConfig.defaultConfig() {
    final arrowLength = 44.0 * 0.2; // 8.8
    final arrowWidth = 8.8 * 0.2; // ~1.76
    final headLength = arrowLength * 0.3; // ~2.64 (front 30%)
    final tailLength = arrowLength * 0.3; // ~2.64 (back 30%)

    return ArrowVertexConfig(
      // Head (arrow tip) - triangular shape at the front
      headVertices: [
        Vector2(50, 0), // Tip (rightmost point)
        Vector2(10 - headLength, -arrowWidth / 2), // Top left
        Vector2(10, arrowWidth / 2), // Bottom left
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

/// Static arrow component with editable polygon colliders
class StaticArrowWithColliders extends SpriteComponent
    with HasGameRef<ArcheryGame> {
  final Vector2 initialPosition;
  final double initialAngleRad;
  final ArrowVertexConfig vertexConfig;

  // Edit mode
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;
  ArrowVertexEditorComponent? _vertexEditor;

  StaticArrowWithColliders({
    required this.initialPosition,
    required this.initialAngleRad,
    required this.vertexConfig,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Load sprite
    sprite = await Sprite.load('arrow.png');
    final originalSize = sprite!.originalSize;
    final spriteScale = 0.2;
    size = originalSize * spriteScale;
    anchor = Anchor.center;
    position = initialPosition;
    angle = initialAngleRad;
  }

  void setEditMode(bool enabled) {
    _isEditMode = enabled;
    print('🎨 Arrow edit mode set to: $_isEditMode');

    if (_isEditMode) {
      // Add vertex editor for all body parts
      if (_vertexEditor == null) {
        _vertexEditor = ArrowVertexEditorComponent(arrow: this);
        add(_vertexEditor!);
        print('✅ Arrow vertex editor added');
        print('   Arrow position: $position');
        print('   Arrow size: $size');
        print('   Head vertices: ${vertexConfig.headVertices.length}');
        print('   Body vertices: ${vertexConfig.bodyVertices.length}');
        print('   Tail vertices: ${vertexConfig.tailVertices.length}');
      } else {
        print('⚠️ Arrow vertex editor already exists');
      }
    } else {
      // Remove vertex editor
      _vertexEditor?.removeFromParent();
      _vertexEditor = null;
      print('❌ Arrow vertex editor removed');
    }
  }

  void printVertexConfig() {
    print('\n═══════════════════════════════════════════════════════');
    print('📐 ARROW VERTEX CONFIGURATION');
    print('═══════════════════════════════════════════════════════');
    print('\n// Head vertices:');
    print('headVertices: [');
    for (final v in vertexConfig.headVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('\n// Body vertices:');
    print('bodyVertices: [');
    for (final v in vertexConfig.bodyVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('\n// Tail vertices:');
    print('tailVertices: [');
    for (final v in vertexConfig.tailVertices) {
      print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
    }
    print('],');
    print('═══════════════════════════════════════════════════════\n');
  }

  List<Vector2> getCurrentVertices(String bodyPart) {
    switch (bodyPart) {
      case 'head':
        return vertexConfig.headVertices;
      case 'body':
        return vertexConfig.bodyVertices;
      case 'tail':
        return vertexConfig.tailVertices;
      default:
        return [];
    }
  }

  void updateVertex(String bodyPart, int index, Vector2 newPosition) {
    switch (bodyPart) {
      case 'head':
        if (index < vertexConfig.headVertices.length) {
          vertexConfig.headVertices[index] = newPosition;
        }
        break;
      case 'body':
        if (index < vertexConfig.bodyVertices.length) {
          vertexConfig.bodyVertices[index] = newPosition;
        }
        break;
      case 'tail':
        if (index < vertexConfig.tailVertices.length) {
          vertexConfig.tailVertices[index] = newPosition;
        }
        break;
    }
  }

  void handlePanStart(DragStartInfo info) {
    if (_vertexEditor == null) return;

    final worldPos = info.eventPosition.widget;
    final vertices = _vertexEditor!.getVertices();

    // Find the closest vertex
    DraggableArrowVertex? closestVertex;
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
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw colored lines for each collider
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
    if (vertexConfig.headVertices.length >= 2) {
      _drawPolygon(canvas, vertexConfig.headVertices, headPaint);
    }

    // Draw body collider (blue)
    if (vertexConfig.bodyVertices.length >= 2) {
      _drawPolygon(canvas, vertexConfig.bodyVertices, bodyPaint);
    }

    // Draw tail collider (green)
    if (vertexConfig.tailVertices.length >= 2) {
      _drawPolygon(canvas, vertexConfig.tailVertices, tailPaint);
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

    // Debug: Draw vertex points as small circles
    final vertexPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (final vertex in vertices) {
      canvas.drawCircle(Offset(vertex.x, vertex.y), 3, vertexPaint);
    }
  }
}

/// Interactive vertex editor component for arrow
class ArrowVertexEditorComponent extends PositionComponent
    with HasGameRef<ArcheryGame>, TapCallbacks {
  final StaticArrowWithColliders arrow;
  List<DraggableArrowVertex> vertices = [];

  ArrowVertexEditorComponent({required this.arrow})
    : super(
        position: Vector2.zero(), // Position relative to arrow (its parent)
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
    final headVertices = arrow.getCurrentVertices('head');
    print('📐 Creating ${headVertices.length} head vertices');
    for (int i = 0; i < headVertices.length; i++) {
      final vertex = DraggableArrowVertex(
        index: i,
        initialPosition: headVertices[i],
        bodyPart: 'head',
        arrow: arrow,
        onUpdate: () {
          // Vertex updated
        },
      );
      vertices.add(vertex);
      add(vertex);
      print('   Head vertex $i at: ${headVertices[i]}');
    }

    // Body vertices (yellow/blue)
    final bodyVertices = arrow.getCurrentVertices('body');
    print('📐 Creating ${bodyVertices.length} body vertices');
    for (int i = 0; i < bodyVertices.length; i++) {
      final vertex = DraggableArrowVertex(
        index: i,
        initialPosition: bodyVertices[i],
        bodyPart: 'body',
        arrow: arrow,
        onUpdate: () {
          // Vertex updated
        },
      );
      vertices.add(vertex);
      add(vertex);
      print('   Body vertex $i at: ${bodyVertices[i]}');
    }

    // Tail vertices (green/cyan)
    final tailVertices = arrow.getCurrentVertices('tail');
    print('📐 Creating ${tailVertices.length} tail vertices');
    for (int i = 0; i < tailVertices.length; i++) {
      final vertex = DraggableArrowVertex(
        index: i,
        initialPosition: tailVertices[i],
        bodyPart: 'tail',
        arrow: arrow,
        onUpdate: () {
          // Vertex updated
        },
      );
      vertices.add(vertex);
      add(vertex);
      print('   Tail vertex $i at: ${tailVertices[i]}');
    }

    print('✅ Total arrow vertices created: ${vertices.length}');
    print('   Arrow world position: ${arrow.position}');
    print('   Arrow size: ${arrow.size}');
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw instructions
    final textPainter = TextPainter(
      text: const TextSpan(
        text:
            'Editing arrow colliders (Click & drag vertices, Press P to print config)\n'
            'Head: Red | Body: Blue | Tail: Green',
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

  List<DraggableArrowVertex> getVertices() => vertices;
}

/// Draggable vertex point for arrow
class DraggableArrowVertex extends PositionComponent
    with HasGameRef<ArcheryGame>, TapCallbacks {
  final int index;
  final String bodyPart;
  final StaticArrowWithColliders arrow;
  final VoidCallback onUpdate;
  bool _isDragging = false;

  bool get isDragging => _isDragging;

  void startDragging() {
    _isDragging = true;
  }

  DraggableArrowVertex({
    required this.index,
    required Vector2 initialPosition,
    required this.bodyPart,
    required this.arrow,
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
      case 'body':
        return _isDragging ? Colors.cyan : Colors.blue;
      case 'tail':
        return _isDragging ? Colors.lightGreen : Colors.green;
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
      // Convert mouse world position to arrow's local space
      final arrowWorldPos = arrow.position;
      final localPos = mouseWorldPos - arrowWorldPos;

      position = localPos;
      arrow.updateVertex(bodyPart, index, localPos);
    }
  }

  void stopDragging() {
    if (_isDragging) {
      _isDragging = false;
      onUpdate();
    }
  }
}
