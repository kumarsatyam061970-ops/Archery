import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/game_client.dart';
import '../network/game_state.dart';
import 'predicted_arrow.dart';
import 'flame_colliders.dart';
import 'arrow_prefab.dart';
import 'static_arrow_editor.dart';

/// Main game class with client-side prediction and server synchronization
class ArcheryGame extends Forge2DGame with KeyboardEvents, PanDetector {
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
  BoyCharacterWithColliders? boyCharacter;
  StaticArrowWithColliders? staticArrowEditor; // Static arrow for editing

  // Arrow Prefab (configure once, instantiate many times)
  late ArrowPrefab arrowPrefab;

  @override
  Color backgroundColor() => Colors.pink[50]!;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    print('🎮 [GAME] Initializing game...');
    
    // Create arrow prefab (configure once, like Unity prefab)
    arrowPrefab = ArrowPrefab(
      config: ArrowPrefabConfig(
        showColliders: true,
        headColor: Colors.red,
        bodyColor: Colors.blue,
        tailColor: Colors.green,
        colliderStrokeWidth: 4.0,
        defaultSpeed: speed,
        defaultGravity: gravity,
      ),
    );
    print('✅ [GAME] Arrow prefab created');
    
    // Note: Collision detection is server-authoritative
    // Forge2D contact listener can be set up here if needed for client-side visual feedback
    // world.contactListener = ArrowContactListener();
    
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

    // Add boy character (target) with editable colliders
    final boyPosition = Vector2(origin.dx + 400, origin.dy);
    boyCharacter = BoyCharacterWithColliders(
      initialPosition: boyPosition,
      vertexConfig: VertexConfig.defaultConfig(),
    );
    await add(boyCharacter!);

    // Add static arrow for editing (doesn't move, just for vertex editing)
    final arrowPosition = Vector2(origin.dx + 200, origin.dy);
    staticArrowEditor = StaticArrowWithColliders(
      initialPosition: arrowPosition,
      initialAngleRad: 0.0, // Pointing right
      vertexConfig: ArrowVertexConfig.defaultConfig(),
    );
    await add(staticArrowEditor!);
    print('✅ [GAME] Static arrow editor added');
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
    // Instantiate arrow from prefab (like Unity's Instantiate)
    final predictedId = 'pred_$clientTimestamp';
    print('   Predicted arrow ID: $predictedId');
    final predicted = arrowPrefab.instantiate(
      arrowId: predictedId,
      position: start,
      angleDeg: angleDeg,
      speed: speed,
      gravity: gravity,
      spawnTimestamp: clientTimestamp,
    );
    predictedArrows[predictedId] = predicted;
    add(predicted);
    print('   ✅ Arrow instantiated from prefab');

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
    // Instantiate arrow from prefab for server-spawned arrows too
    final arrow = arrowPrefab.instantiate(
      arrowId: arrowId,
      position: startPos,
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
  void onPanStart(DragStartInfo info) {
    // Forward to arrow editor if in edit mode
    if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
      print('🎮 Game: Pan start in arrow edit mode, forwarding to arrow editor');
      staticArrowEditor!.handlePanStart(info);
      return;
    }
    // Forward to boy character if in edit mode
    if (boyCharacter != null && boyCharacter!.isEditMode) {
      print('🎮 Game: Pan start in edit mode, forwarding to boy character');
      boyCharacter!.handlePanStart(info);
      return;
    }
    // Otherwise handle aim input
    _updateAim(info.eventPosition.widget);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    // Forward to arrow editor if in edit mode
    if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
      staticArrowEditor!.handlePanUpdate(info);
      return;
    }
    // Forward to boy character if in edit mode
    if (boyCharacter != null && boyCharacter!.isEditMode) {
      boyCharacter!.handlePanUpdate(info);
      return;
    }
    // Otherwise handle aim input
    _updateAim(info.eventPosition.widget);
  }

  @override
  void onPanEnd(DragEndInfo info) {
    // Forward to arrow editor if in edit mode
    if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
      staticArrowEditor!.handlePanEnd(info);
      return;
    }
    // Forward to boy character if in edit mode
    if (boyCharacter != null && boyCharacter!.isEditMode) {
      boyCharacter!.handlePanEnd(info);
      return;
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        // Disable arrow spawning when in edit mode
        if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
          print('⚠️ Cannot spawn arrow while editing arrow vertices');
          return KeyEventResult.handled;
        }
        if (boyCharacter != null && boyCharacter!.isEditMode) {
          print('⚠️ Cannot spawn arrow while editing character vertices');
          return KeyEventResult.handled;
        }
        _spawnArrow();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
        // Toggle arrow edit mode (E key for arrow editing)
        if (staticArrowEditor != null) {
          final wasEditMode = staticArrowEditor!.isEditMode;
          final newEditMode = !wasEditMode;
          staticArrowEditor!.setEditMode(newEditMode);
          
          // Disable/enable aim input based on edit mode
          if (newEditMode) {
            // Entering edit mode - remove aim input to prevent interference
            if (aimInput.isMounted) {
              aimInput.removeFromParent();
            }
            // Also disable boy character edit mode if active
            if (boyCharacter != null && boyCharacter!.isEditMode) {
              boyCharacter!.setEditMode(false);
            }
          } else {
            // Exiting edit mode - re-add aim input
            if (!aimInput.isMounted) {
              add(aimInput);
            }
          }
          print('🎨 Arrow edit mode: ${newEditMode ? "ON" : "OFF"}');
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
        // Toggle boy character edit mode (C key for character editing)
        if (boyCharacter != null) {
          final wasEditMode = boyCharacter!.isEditMode;
          final newEditMode = !wasEditMode;
          boyCharacter!.setEditMode(newEditMode);
          
          // Disable/enable aim input based on edit mode
          if (newEditMode) {
            // Entering edit mode - remove aim input to prevent interference
            if (aimInput.isMounted) {
              aimInput.removeFromParent();
            }
            // Also disable arrow edit mode if active
            if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
              staticArrowEditor!.setEditMode(false);
            }
          } else {
            // Exiting edit mode - re-add aim input
            if (!aimInput.isMounted) {
              add(aimInput);
            }
          }
          print('🎨 Character edit mode: ${newEditMode ? "ON" : "OFF"}');
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
        // Print vertex configuration
        if (staticArrowEditor != null && staticArrowEditor!.isEditMode) {
          staticArrowEditor!.printVertexConfig();
        } else if (boyCharacter != null) {
          boyCharacter!.printVertexConfig();
        }
        return KeyEventResult.handled;
      }
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


/// ContactListener to detect collisions between arrows and the boy character
class ArrowContactListener extends ContactListener {
  @override
  void beginContact(Contact contact) {
    final fixtureA = contact.fixtureA;
    final fixtureB = contact.fixtureB;

    final bodyA = fixtureA.body.userData;
    final bodyB = fixtureB.body.userData;

    // Check if one is the boy character
    BoyCharacterWithColliders? boy;
    String? bodyPart;

    if (bodyA is BoyCharacterWithColliders) {
      boy = bodyA;
      // Check which body part was hit based on fixture userData
      if (fixtureA.userData is String) {
        bodyPart = fixtureA.userData as String;
      }
    } else if (bodyB is BoyCharacterWithColliders) {
      boy = bodyB;
      // Check which body part was hit based on fixture userData
      if (fixtureB.userData is String) {
        bodyPart = fixtureB.userData as String;
      }
    }

    if (boy != null && bodyPart != null) {
      print('🎯 [FORGE2D] Collision detected on: $bodyPart');
      boy.onBodyPartHit(bodyPart, contact);
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

