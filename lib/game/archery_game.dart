import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/game_client.dart';
import '../network/game_state.dart';
import 'predicted_arrow.dart';
import 'character_config.dart';

/// Main game class with client-side prediction and server synchronization
class ArcheryGame extends FlameGame with KeyboardEvents, PanDetector, HasCollisionDetection {
  // Game configuration
  Offset origin = const Offset(25, 350);
  double gravity = 60;
  double speed = 300;
  Vector2 aimDir = Vector2(1, 0);

  // Network
  late GameClient gameClient;
  GameState gameState = GameState();
  final Map<String, PredictedArrow> predictedArrows = {};

  // UI Components
  late StaticArrowComponent staticArrow;
  late AimInputComponent aimInput;

  @override
  Color backgroundColor() => Colors.pink[50]!;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    print('🎮 [GAME] Initializing game...');
    
    // Initialize network client
    print('🌐 [GAME] Creating GameClient...');
    gameClient = GameClient();
    _setupNetworkCallbacks();

    // Connect to server (change URL as needed)
    const serverUrl = 'ws://localhost:8080/game';
    print('🌐 [GAME] Connecting to server: $serverUrl');
    final connected = await gameClient.connect(serverUrl);
    if (connected) {
      print('✅ [GAME] Connected to server successfully');
      print('🚪 [GAME] Joining room: room1');
      gameClient.joinRoom('room1');
    } else {
      print('❌ [GAME] Failed to connect to server');
    }

    // Add UI components
    add(AxesComponent(origin: origin));
    add(Line330Component(origin: origin, length: 800));

    aimInput = AimInputComponent(onAim: _updateAim);
    add(aimInput);

    // Add static aiming arrow
    staticArrow = StaticArrowComponent(
      angleDeg: 330.0,
      initialPosition: Vector2(origin.dx, origin.dy),
    );
    await add(staticArrow);

    // Add boy character (target)
    final boyPosition = Vector2(origin.dx + 400, origin.dy);
    await add(BoyCharacterComponent(initialPosition: boyPosition));
  }

  void _setupNetworkCallbacks() {
    print('🔧 [GAME] Setting up network callbacks...');
    
    gameClient.onArrowSpawned = (data) {
      print('🏹 [GAME] Arrow spawned callback triggered');
      final arrowId = data['arrow_id'] as String;
      final startX = (data['start_x'] as num).toDouble();
      final startY = (data['start_y'] as num).toDouble();
      final angle = (data['angle'] as num).toDouble();
      final speed = (data['speed'] as num).toDouble();
      final spawnTime = data['spawn_time'] as int;

      print('   Arrow ID: $arrowId');
      print('   Start: ($startX, $startY)');
      print('   Angle: $angle°');
      print('   Speed: $speed');
      print('   Spawn time: $spawnTime');

      // Check if this is our predicted arrow
      PredictedArrow? predicted;
      try {
        predicted = predictedArrows.values
            .firstWhere((a) => !a.confirmedByServer);
        print('   Found unconfirmed predicted arrow: ${predicted.arrowId}');
      } catch (e) {
        predicted = null;
        print('   No unconfirmed predicted arrow found');
      }

      if (predicted != null && !predicted.confirmedByServer) {
        // Reconcile our prediction - update the arrow ID to match server
        print('   ✅ Reconciling predicted arrow with server');
        final oldId = predicted.arrowId;
        predicted.arrowId = arrowId; // Update to server-assigned ID
        predicted.confirmedByServer = true;
        
        // Update the map key from predicted ID to server ID
        predictedArrows.remove(oldId);
        predictedArrows[arrowId] = predicted;
        
        // Don't set server position yet - wait for game_state update with actual position
        print('   ✅ Arrow ID updated from $oldId to $arrowId');
      } else {
        // Server spawned arrow from another player
        print('   👤 Spawning server arrow from another player');
        _spawnServerArrow(
          arrowId: arrowId,
          startPos: Vector2(startX, startY),
          angleDeg: angle,
          speed: speed,
          spawnTime: spawnTime,
        );
      }
    };

    gameClient.onHitDetected = (data) {
      print('🎯 [GAME] Hit detected callback triggered');
      final arrowId = data['arrow_id'] as String;
      final bodyPart = data['body_part'] as String?;
      print('   Arrow ID: $arrowId');
      print('   Body part: $bodyPart');

      // Remove arrow
      final arrow = predictedArrows[arrowId];
      if (arrow != null) {
        print('   Removing arrow from game');
        arrow.removeFromParent();
        predictedArrows.remove(arrowId);
      } else {
        print('   ⚠️ Arrow not found in predicted arrows map');
      }

      print('🎯 [GAME] Hit detected: $bodyPart');
    };

    gameClient.onGameStateUpdate = (data) {
      final tick = data['tick'] as int? ?? 0;
      final arrowsCount = (data['arrows'] as Map?)?.length ?? 0;
      final playersCount = (data['players'] as Map?)?.length ?? 0;
      
      // Only log game_state every 60 ticks (once per second) to reduce noise
      if (tick % 60 == 0) {
        print('🎮 [GAME] Game state update (tick: $tick)');
        print('   Server time: ${data['server_time']}');
        print('   Arrows count: $arrowsCount');
        print('   Players count: $playersCount');
      }
      
      gameState.updateFromServer(data);

      // Reconcile all predicted arrows with server state
      int reconciledCount = 0;
      for (final arrow in predictedArrows.values) {
        if (gameState.arrows.containsKey(arrow.arrowId)) {
          final serverArrow = gameState.arrows[arrow.arrowId]!;
          arrow.reconcileWithServer(
            serverArrow.position,
            (serverArrow.spawnTime / 1000.0),
          );
          reconciledCount++;
        }
      }
      if (reconciledCount > 0) {
        print('   ✅ Reconciled $reconciledCount arrow(s) with server state');
      }
    };
    
    print('✅ [GAME] Network callbacks set up');
  }

  void _updateAim(Vector2 target) {
    final originVec = Vector2(origin.dx, origin.dy);
    final dir = target - originVec;
    if (dir.length2 > 1e-4) {
      final angleDeg = math.atan2(dir.y, dir.x) * 180 / math.pi;
      final clampedDeg = angleDeg.clamp(-90.0, 0.0);
      final rad = clampedDeg * math.pi / 180;
      aimDir = Vector2(math.cos(rad), math.sin(rad));
    }

    // Send aim update to server (optional, for spectator view)
    gameClient.sendAimUpdate(aimDir);
  }

  void _spawnArrow() {
    print('🏹 [GAME] Spawning arrow (client-side prediction)');
    final start = Vector2(origin.dx, origin.dy);
    final angleDeg = (math.atan2(aimDir.y, aimDir.x) * 180 / math.pi);
    final clientTimestamp = DateTime.now().millisecondsSinceEpoch;

    print('   Start position: (${start.x.toStringAsFixed(2)}, ${start.y.toStringAsFixed(2)})');
    print('   Angle: ${angleDeg.toStringAsFixed(2)}°');
    print('   Speed: $speed');
    print('   Gravity: $gravity');
    print('   Client timestamp: $clientTimestamp');

    // 1. Client-side prediction (immediate feedback)
    final predictedId = 'pred_$clientTimestamp';
    print('   Predicted arrow ID: $predictedId');
    final predicted = PredictedArrow(
      arrowId: predictedId,
      startPos: start,
      angleDeg: angleDeg,
      speed: speed,
      gravity: gravity,
      spawnTimestamp: clientTimestamp,
    );
    predictedArrows[predictedId] = predicted;
    add(predicted);
    print('   ✅ Predicted arrow added to game');

    // 2. Send to server (authoritative)
    print('   📤 Sending arrow shot to server...');
    gameClient.sendArrowShot(
      startPos: start,
      angleDeg: angleDeg,
      speed: speed,
      clientTimestamp: clientTimestamp,
    );
  }

  void _spawnServerArrow({
    required String arrowId,
    required Vector2 startPos,
    required double angleDeg,
    required double speed,
    required int spawnTime,
  }) {
    final arrow = PredictedArrow(
      arrowId: arrowId,
      startPos: startPos,
      angleDeg: angleDeg,
      speed: speed,
      gravity: gravity,
      spawnTimestamp: spawnTime,
    );
    arrow.confirmedByServer = true;
    predictedArrows[arrowId] = arrow;
    add(arrow);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (staticArrow.isLoaded && aimDir.length2 > 1e-4) {
      staticArrow.angle = math.atan2(aimDir.y, aimDir.x);
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

  @override
  void onRemove() {
    gameClient.disconnect();
    super.onRemove();
  }
}

// =======================
// UI Components
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

    canvas.drawLine(
      Offset(-axisLength, origin.dy),
      Offset(axisLength, origin.dy),
      paintX,
    );
    canvas.drawLine(
      Offset(origin.dx, origin.dy - axisLength),
      Offset(origin.dx, origin.dy + axisLength),
      paintY,
    );
  }
}

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

class StaticArrowComponent extends SpriteComponent {
  StaticArrowComponent({
    required this.angleDeg,
    required this.initialPosition,
  }) : super(anchor: Anchor.center);

  final double angleDeg;
  final Vector2 initialPosition;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await Sprite.load('arrow.png');
    const baseWidth = 140.0;
    final aspect = sprite!.originalSize.y / sprite!.originalSize.x;
    size = Vector2(baseWidth, baseWidth * aspect);
    angle = angleDeg * math.pi / 180.0;
    position = initialPosition;
  }
}

class AimInputComponent extends PositionComponent
    with HasGameRef<ArcheryGame>, TapCallbacks {
  AimInputComponent({required this.onAim});

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

class BoyCharacterComponent extends SpriteComponent 
    with HasGameRef<ArcheryGame>, CollisionCallbacks {
  BoyCharacterComponent({required this.initialPosition});

  final Vector2 initialPosition;
  
  // Body part colliders (for client-side visual feedback)
  late PolygonHitbox headCollider;
  late PolygonHitbox upperBodyCollider;
  late PolygonHitbox lowerBodyCollider;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = await Sprite.load('boy.png');
    const targetWidth = 100.0;
    final aspectRatio = sprite!.originalSize.y / sprite!.originalSize.x;
    size = Vector2(targetWidth, targetWidth * aspectRatio);
    anchor = Anchor.center;
    position = initialPosition;

    // Get polygon vertices from config (relative to component center)
    final headVertices = CharacterBodyPartConfig.getHeadVertices();
    final upperBodyVertices = CharacterBodyPartConfig.getUpperBodyVertices();
    final lowerBodyVertices = CharacterBodyPartConfig.getLowerBodyVertices();

    // Add head polygon collider
    headCollider = PolygonHitbox(headVertices);
    add(headCollider);

    // Add upper body polygon collider
    upperBodyCollider = PolygonHitbox(upperBodyVertices);
    add(upperBodyCollider);

    // Add lower body polygon collider
    lowerBodyCollider = PolygonHitbox(lowerBodyVertices);
    add(lowerBodyCollider);
  }

  @override
  bool onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PredictedArrow) {
      // Determine which body part was hit based on intersection points
      final hitBodyPart = _getHitBodyPart(intersectionPoints);
      print('🎯 [BOY] Arrow ${other.arrowId} collision detected on: $hitBodyPart');
      // Server is authoritative - this is just for visual feedback
    }
    return true; // Allow collision to be processed
  }

  String _getHitBodyPart(Set<Vector2> intersectionPoints) {
    if (intersectionPoints.isEmpty) return 'upperBody';
    
    // Get average Y position of collision points (relative to character center)
    final avgY = intersectionPoints.map((p) => p.y - position.y).reduce((a, b) => a + b) / intersectionPoints.length;
    final charHeight = size.y;
    
    // Determine body part based on Y position (matching server logic)
    if (avgY < -charHeight * 0.2) {
      return 'head';
    } else if (avgY < charHeight * 0.2) {
      return 'upperBody';
    } else {
      return 'lowerBody';
    }
  }
}

