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
          gravity: forge2d.Vector2(0, 20), // Apply gravity so the physics engine creates a parabolic path
          zoom: 1.0,
        );

  @override
  Color backgroundColor() => Colors.white;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set arrow starting position (bottom left area, like a bow)
    _arrowStartPosition = Vector2(100, size.y - 150);

    _arrow = ArrowComponent(
      startPosition: _arrowStartPosition,
    );
    await add(_arrow);
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

class ArrowComponent extends BodyComponent<ArcheryGame> {
  final Vector2 startPosition;
  Vector2 aimDirection = Vector2(1, 0);
  double pullStrength = 0.0;
  bool isFlying = false;
  Vector2 spriteSize = Vector2(44, 8.8); // Default size (will be updated after sprite loads)
  late SpriteComponent spriteComponent;

  // Physics constants
  static const double baseSpeed = 15.0; // Base speed in Forge2D units per second

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
      anchor: Anchor.centerLeft,
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
    body.gravityScale = 1;

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
      final speed = baseSpeed * (0.5 + pullStrength * 1.5); // Speed range: 0.5x to 2x base
      final velocity = forge2d.Vector2(
        aimDirection.x * speed,
        aimDirection.y * speed,
      );

      // Apply initial velocity to the body; Box2D gravity will create the parabolic path
      body.setAwake(true);
      body.linearVelocity = velocity;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (isFlying) {
      final currentVelocity = body.linearVelocity;
      if (currentVelocity.length2 > 0) {
        spriteComponent.angle = math.atan2(currentVelocity.y, currentVelocity.x);
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
