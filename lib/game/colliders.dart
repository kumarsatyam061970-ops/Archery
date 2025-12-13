// import 'package:flame/components.dart';
// import 'package:flame/events.dart';
// import 'package:flame/game.dart';
// import 'package:flame_forge2d/flame_forge2d.dart';
// import 'package:flutter/material.dart';
// import 'package:forge2d/forge2d.dart' as forge2d;
// import '../main.dart' show ArcheryGame, ArrowProjectile;

// /// ContactListener to detect collisions between arrows and the boy character
// class ArrowContactListener extends ContactListener {
//   @override
//   void beginContact(Contact contact) {
//     final fixtureA = contact.fixtureA;
//     final fixtureB = contact.fixtureB;

//     final bodyA = fixtureA.body.userData;
//     final bodyB = fixtureB.body.userData;

//     // Debug: print all contacts to see what's happening
//     print(
//       '🔍 Contact detected: bodyA=${bodyA.runtimeType}, bodyB=${bodyB.runtimeType}',
//     );
//     print(
//       '   fixtureA.userData=${fixtureA.userData}, fixtureB.userData=${fixtureB.userData}',
//     );

//     // Check if one is an arrow and the other is the boy
//     ArrowProjectile? arrow;
//     BoyCharacter? boy;
//     String? bodyPart;

//     if (bodyA is ArrowProjectile && bodyB is BoyCharacter) {
//       arrow = bodyA;
//       boy = bodyB;
//       // Check which body part was hit based on fixture userData
//       if (fixtureB.userData is String) {
//         bodyPart = fixtureB.userData as String;
//       }
//       print('✅ Arrow (A) hit Boy (B), body part: $bodyPart');
//     } else if (bodyB is ArrowProjectile && bodyA is BoyCharacter) {
//       arrow = bodyB;
//       boy = bodyA;
//       // Check which body part was hit based on fixture userData
//       if (fixtureA.userData is String) {
//         bodyPart = fixtureA.userData as String;
//       }
//       print('✅ Arrow (B) hit Boy (A), body part: $bodyPart');
//     }

//     if (arrow != null && boy != null) {
//       print('🎯 Arrow hit boy! Body part: ${bodyPart ?? "unknown"}');
//       if (bodyPart != null) {
//         boy.onBodyPartHit(bodyPart, arrow);
//       }
//       // Remove the arrow after collision
//       arrow.removeFromParent();
//     }
//   }

//   @override
//   void endContact(Contact contact) {
//     // Called when contact ends (optional)
//   }

//   @override
//   void preSolve(Contact contact, Manifold oldManifold) {
//     // Called before collision resolution (optional)
//   }

//   @override
//   void postSolve(Contact contact, ContactImpulse impulse) {
//     // Called after collision resolution (optional)
//   }
// }

// /// Configuration for body part vertices
// class VertexConfig {
//   final List<Vector2> headVertices;
//   final List<Vector2> upperBodyVertices;
//   final List<Vector2> legsVertices;

//   VertexConfig({
//     required this.headVertices,
//     required this.upperBodyVertices,
//     required this.legsVertices,
//   });

//   /// Default configuration (can be replaced with custom vertices)
//   factory VertexConfig.defaultConfig() {
//     return VertexConfig(
//       headVertices: [
//         Vector2(-35, -52.5), // Top left
//         Vector2(35, -52.5), // Top right
//         Vector2(35, -40), // Right upper
//         Vector2(33.25, -22.5), // Right middle
//         Vector2(29.75, -7.5), // Right lower
//         Vector2(-29.75, -7.5), // Left lower
//         Vector2(-33.25, -22.5), // Left middle
//         Vector2(-35, -40), // Left upper
//       ],
//       upperBodyVertices: [
//         Vector2(-40, -7.5), // Top left (shoulder)
//         Vector2(40, -7.5), // Top right (shoulder)
//         Vector2(42, 37.5), // Bottom right (waist)
//         Vector2(-42, 37.5), // Bottom left (waist)
//       ],
//       legsVertices: [
//         Vector2(-5, 13.5), // Top left
//         Vector2(15, 13.5), // Top right
//         Vector2(16.5, 60), // Bottom right
//         Vector2(20, 69.75), // Right foot outer
//         Vector2(-20, 70.5), // Right foot inner
//         Vector2(-10, 67.5), // Left foot inner
//         Vector2(-20, 167.5), // Left foot outer
//         Vector2(-16.5, 80), // Bottom left
//       ],
//     );
//   }

//   /// Create from Forge2D vectors
//   factory VertexConfig.fromForge2D({
//     required List<forge2d.Vector2> head,
//     required List<forge2d.Vector2> upperBody,
//     required List<forge2d.Vector2> legs,
//   }) {
//     return VertexConfig(
//       headVertices: head
//           .map((v) => Vector2(v.x.toDouble(), v.y.toDouble()))
//           .toList(),
//       upperBodyVertices: upperBody
//           .map((v) => Vector2(v.x.toDouble(), v.y.toDouble()))
//           .toList(),
//       legsVertices: legs
//           .map((v) => Vector2(v.x.toDouble(), v.y.toDouble()))
//           .toList(),
//     );
//   }
// }

// class BoyCharacter extends BodyComponent<ArcheryGame> {
//   final Vector2 position;
//   final VertexConfig vertexConfig;
//   late SpriteComponent spriteComponent;
//   Vector2 spriteSize = Vector2.zero();

//   // Store vertices for rendering (in Forge2D format)
//   List<forge2d.Vector2> headVertices = [];
//   List<forge2d.Vector2> upperBodyVertices = [];
//   List<forge2d.Vector2> legsVertices = [];

//   // Edit mode
//   bool _isEditMode = false;
//   String _editingBodyPart = 'head';
//   VertexEditorComponent? _vertexEditor;

//   BoyCharacter({required this.position, required this.vertexConfig});

//   // Make colliders visible for debugging (set renderBody = true to see them)
//   @override
//   Paint get paint => Paint()
//     ..color = Colors.blue.withOpacity(0.3)
//     ..style = PaintingStyle.stroke
//     ..strokeWidth = 2.0;

//   @override
//   bool get renderBody => false; // We'll render custom green lines instead

//   @override
//   Future<void> onLoad() async {
//     // Load sprite FIRST before calling super.onLoad() so spriteSize is available for createBody()
//     final sprite = await Sprite.load('boy.png');
//     final originalSize = sprite.originalSize;

//     // Set x size to 100 and calculate y based on aspect ratio
//     const targetWidth = 100.0;
//     final aspectRatio = originalSize.y / originalSize.x;
//     spriteSize = Vector2(targetWidth, targetWidth * aspectRatio);

//     // Now call super.onLoad() which will call createBody()
//     await super.onLoad();

//     spriteComponent = SpriteComponent(
//       sprite: sprite,
//       size: spriteSize, // x=100, y calculated from aspect ratio
//       anchor: Anchor.center,
//     );
//     add(spriteComponent);
//   }

//   void setEditMode(bool enabled, String bodyPart) {
//     _isEditMode = enabled;
//     _editingBodyPart = bodyPart;

//     if (_isEditMode) {
//       // Add vertex editor
//       if (_vertexEditor == null) {
//         _vertexEditor = VertexEditorComponent(
//           boyCharacter: this,
//           bodyPart: bodyPart,
//         );
//         add(_vertexEditor!);
//       } else {
//         _vertexEditor!.setBodyPart(bodyPart);
//       }
//     } else {
//       // Remove vertex editor
//       _vertexEditor?.removeFromParent();
//       _vertexEditor = null;
//     }
//   }

//   void printVertexConfig() {
//     print('\n═══════════════════════════════════════════════════════');
//     print('📐 VERTEX CONFIGURATION');
//     print('═══════════════════════════════════════════════════════');
//     print('\n// Head vertices:');
//     print('headVertices: [');
//     for (final v in vertexConfig.headVertices) {
//       print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
//     }
//     print('],');
//     print('\n// Upper body vertices:');
//     print('upperBodyVertices: [');
//     for (final v in vertexConfig.upperBodyVertices) {
//       print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
//     }
//     print('],');
//     print('\n// Legs vertices:');
//     print('legsVertices: [');
//     for (final v in vertexConfig.legsVertices) {
//       print('  Vector2(${v.x.toStringAsFixed(1)}, ${v.y.toStringAsFixed(1)}),');
//     }
//     print('],');
//     print('═══════════════════════════════════════════════════════\n');
//   }

//   List<Vector2> getCurrentVertices(String bodyPart) {
//     switch (bodyPart) {
//       case 'head':
//         return vertexConfig.headVertices;
//       case 'upperBody':
//         return vertexConfig.upperBodyVertices;
//       case 'legs':
//         return vertexConfig.legsVertices;
//       default:
//         return [];
//     }
//   }

//   void updateVertex(String bodyPart, int index, Vector2 newPosition) {
//     switch (bodyPart) {
//       case 'head':
//         if (index < vertexConfig.headVertices.length) {
//           vertexConfig.headVertices[index] = newPosition;
//           headVertices[index] = forge2d.Vector2(newPosition.x, newPosition.y);
//         }
//         break;
//       case 'upperBody':
//         if (index < vertexConfig.upperBodyVertices.length) {
//           vertexConfig.upperBodyVertices[index] = newPosition;
//           upperBodyVertices[index] = forge2d.Vector2(
//             newPosition.x,
//             newPosition.y,
//           );
//         }
//         break;
//       case 'legs':
//         if (index < vertexConfig.legsVertices.length) {
//           vertexConfig.legsVertices[index] = newPosition;
//           legsVertices[index] = forge2d.Vector2(newPosition.x, newPosition.y);
//         }
//         break;
//     }
//   }

//   void handlePanStart(DragStartInfo info) {
//     if (_vertexEditor == null) return;
//     final worldPos = info.eventPosition.widget;
//     final vertices = _vertexEditor!.getVertices();
//     for (final vertex in vertices) {
//       final vertexWorldPos = position + vertex.position;
//       final distance = (worldPos - vertexWorldPos).length;
//       if (distance < 20) {
//         // Start dragging this vertex
//         vertex._isDragging = true;
//         break;
//       }
//     }
//   }

//   void handlePanUpdate(DragUpdateInfo info) {
//     if (_vertexEditor == null) return;
//     final worldPos = info.eventPosition.widget;
//     final vertices = _vertexEditor!.getVertices();
//     for (final vertex in vertices) {
//       if (vertex.isDragging) {
//         vertex.updatePosition(worldPos);
//         break;
//       }
//     }
//   }

//   void handlePanEnd(DragEndInfo info) {
//     if (_vertexEditor == null) return;
//     final vertices = _vertexEditor!.getVertices();
//     for (final vertex in vertices) {
//       vertex.stopDragging();
//     }
//   }

//   @override
//   forge2d.Body createBody() {
//     // Ensure spriteSize is valid (should be set in onLoad before super.onLoad())
//     // Use fallback size if spriteSize is not yet set
//     final effectiveWidth = spriteSize.x > 0 ? spriteSize.x : 100.0;
//     final effectiveHeight = spriteSize.y > 0 ? spriteSize.y : 150.0;

//     final bodyDef = forge2d.BodyDef(
//       type: forge2d.BodyType.dynamic,
//       position: forge2d.Vector2(position.x, position.y),
//       angle: 0.0,
//       fixedRotation: true,
//     );

//     final body = world.createBody(bodyDef);

//     // Convert VertexConfig to Forge2D vectors
//     headVertices = vertexConfig.headVertices
//         .map((v) => forge2d.Vector2(v.x, v.y))
//         .toList();
//     upperBodyVertices = vertexConfig.upperBodyVertices
//         .map((v) => forge2d.Vector2(v.x, v.y))
//         .toList();
//     legsVertices = vertexConfig.legsVertices
//         .map((v) => forge2d.Vector2(v.x, v.y))
//         .toList();

//     // Create head fixture
//     final headShape = forge2d.PolygonShape()..set(headVertices);
//     final headFixture = forge2d.FixtureDef(headShape)
//       ..density = 1.0
//       ..friction = 0.3
//       ..restitution = 0.1
//       ..isSensor = false;
//     final headFixtureObj = body.createFixture(headFixture);
//     headFixtureObj.userData = 'head';

//     // Create upper body fixture
//     final upperBodyShape = forge2d.PolygonShape()..set(upperBodyVertices);
//     final upperBodyFixture = forge2d.FixtureDef(upperBodyShape)
//       ..density = 1.0
//       ..friction = 0.3
//       ..restitution = 0.1
//       ..isSensor = false;
//     final upperBodyFixtureObj = body.createFixture(upperBodyFixture);
//     upperBodyFixtureObj.userData = 'upperBody';

//     // Create legs fixture
//     final legsShape = forge2d.PolygonShape()..set(legsVertices);
//     final legsFixture = forge2d.FixtureDef(legsShape)
//       ..density = 1.0
//       ..friction = 0.5
//       ..restitution = 0.1
//       ..isSensor = false;
//     final legsFixtureObj = body.createFixture(legsFixture);
//     legsFixtureObj.userData = 'legs';

//     body.userData = this;

//     // Set gravity to zero so the boy stays in place
//     body.gravityScale = forge2d.Vector2.zero();
//     body
//       ..setAwake(true)
//       ..setActive(true);

//     return body;
//   }

//   @override
//   void render(Canvas canvas) {
//     super.render(canvas);

//     // Draw green lines for each collider
//     final greenPaint = Paint()
//       ..color = Colors.green
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3.0;

//     // Draw head collider in green
//     if (headVertices.isNotEmpty) {
//       _drawPolygon(canvas, headVertices, greenPaint);
//     }

//     // Draw upper body collider in green
//     if (upperBodyVertices.isNotEmpty) {
//       _drawPolygon(canvas, upperBodyVertices, greenPaint);
//     }

//     // Draw legs collider in green
//     if (legsVertices.isNotEmpty) {
//       _drawPolygon(canvas, legsVertices, greenPaint);
//     }
//   }

//   void _drawPolygon(
//     Canvas canvas,
//     List<forge2d.Vector2> vertices,
//     Paint paint,
//   ) {
//     if (vertices.isEmpty) return;

//     final path = Path();

//     // Convert Forge2D vertices to Flutter Offsets
//     // Note: Canvas is already transformed by BodyComponent's renderTree,
//     // so vertices are in local space (relative to body center)
//     final offsets = vertices
//         .map((v) => Offset(v.x.toDouble(), v.y.toDouble()))
//         .toList();

//     // Draw the polygon
//     path.moveTo(offsets.first.dx, offsets.first.dy);
//     for (var i = 1; i < offsets.length; i++) {
//       path.lineTo(offsets[i].dx, offsets[i].dy);
//     }
//     path.close(); // Close the polygon

//     canvas.drawPath(path, paint);
//   }

//   void onBodyPartHit(String bodyPart, Object other) {
//     print('Body part hit: $bodyPart');
//     // Handle different body part hits
//     switch (bodyPart) {
//       case 'head':
//         print('Critical hit on head!');
//         break;
//       case 'upperBody':
//         print('Hit on upper body!');
//         break;
//       case 'legs':
//         print('Hit on legs!');
//         break;
//     }
//   }
// }

// /// Interactive vertex editor component
// class VertexEditorComponent extends Component
//     with HasGameRef<ArcheryGame>, TapCallbacks {
//   final BoyCharacter boyCharacter;
//   String bodyPart;
//   List<DraggableVertex> vertices = [];

//   VertexEditorComponent({required this.boyCharacter, required this.bodyPart});

//   void setBodyPart(String newBodyPart) {
//     bodyPart = newBodyPart;
//     _updateVertices();
//   }

//   @override
//   Future<void> onLoad() async {
//     await super.onLoad();
//     _updateVertices();
//   }

//   void _updateVertices() {
//     // Remove old vertices
//     for (final vertex in vertices) {
//       vertex.removeFromParent();
//     }
//     vertices.clear();

//     // Create draggable vertices for current body part
//     final currentVertices = boyCharacter.getCurrentVertices(bodyPart);
//     for (int i = 0; i < currentVertices.length; i++) {
//       final vertex = DraggableVertex(
//         index: i,
//         initialPosition: currentVertices[i],
//         bodyPart: bodyPart,
//         boyCharacter: boyCharacter,
//         onUpdate: () {
//           // Update physics body when vertex moves
//           // Note: Forge2D doesn't support dynamic vertex updates easily,
//           // so we'd need to recreate the body. For now, just update the visual.
//         },
//       );
//       vertices.add(vertex);
//       add(vertex);
//     }
//   }

//   @override
//   void render(Canvas canvas) {
//     super.render(canvas);

//     // Draw instructions
//     final textPainter = TextPainter(
//       text: TextSpan(
//         text:
//             'Editing: $bodyPart (Click & drag vertices, Press P to print config)',
//         style: const TextStyle(
//           color: Colors.yellow,
//           fontSize: 16,
//           fontWeight: FontWeight.bold,
//           shadows: [Shadow(color: Colors.black, blurRadius: 4)],
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     )..layout();

//     textPainter.paint(canvas, const Offset(10, 10));
//   }

//   List<DraggableVertex> getVertices() => vertices;
// }

// /// Draggable vertex point
// class DraggableVertex extends PositionComponent
//     with HasGameRef<ArcheryGame>, TapCallbacks {
//   final int index;
//   final String bodyPart;
//   final BoyCharacter boyCharacter;
//   final VoidCallback onUpdate;
//   bool _isDragging = false;

//   bool get isDragging => _isDragging;

//   DraggableVertex({
//     required this.index,
//     required Vector2 initialPosition,
//     required this.bodyPart,
//     required this.boyCharacter,
//     required this.onUpdate,
//   }) : super(
//           position: initialPosition,
//           size: Vector2(20, 20),
//           anchor: Anchor.center,
//         );

//   @override
//   Future<void> onLoad() async {
//     await super.onLoad();
//   }

//   @override
//   void render(Canvas canvas) {
//     super.render(canvas);

//     // Draw vertex circle
//     final paint = Paint()
//       ..color = _isDragging ? Colors.red : Colors.yellow
//       ..style = PaintingStyle.fill;
//     final borderPaint = Paint()
//       ..color = Colors.black
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2;

//     canvas.drawCircle(Offset.zero, 8, paint);
//     canvas.drawCircle(Offset.zero, 8, borderPaint);

//     // Draw index number
//     final textPainter = TextPainter(
//       text: TextSpan(
//         text: '$index',
//         style: const TextStyle(
//           color: Colors.black,
//           fontSize: 10,
//           fontWeight: FontWeight.bold,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     )..layout();

//     textPainter.paint(
//       canvas,
//       Offset(-textPainter.width / 2, -textPainter.height / 2),
//     );
//   }

//   @override
//   bool onTapDown(TapDownEvent event) {
//     _isDragging = true;
//     return true;
//   }

//   @override
//   void update(double dt) {
//     super.update(dt);
//     // Mouse tracking will be handled by the parent editor component
//   }

//   void updatePosition(Vector2 mouseWorldPos) {
//     if (_isDragging) {
//       // Convert mouse world position to boy's local space
//       final boyWorldPos = boyCharacter.position;
//       final localPos = mouseWorldPos - boyWorldPos;

//       position = localPos;
//       boyCharacter.updateVertex(bodyPart, index, localPos);
//     }
//   }

//   void stopDragging() {
//     if (_isDragging) {
//       _isDragging = false;
//       onUpdate();
//     }
//   }
// }
