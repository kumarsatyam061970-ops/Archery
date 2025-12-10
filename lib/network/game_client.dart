import 'dart:convert';
import 'package:flame/components.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for real-time game communication
class GameClient {
  WebSocketChannel? _channel;
  String? _playerId;
  String? _roomId;
  bool _connected = false;

  // Callbacks for game events
  Function(Map<String, dynamic>)? onGameStateUpdate;
  Function(Map<String, dynamic>)? onArrowSpawned;
  Function(Map<String, dynamic>)? onHitDetected;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(Map<String, dynamic>)? onPlayerLeft;
  Function(String)? onError;
  Function()? onDisconnected;

  /// Connect to game server
  Future<bool> connect(String serverUrl) async {
    print('🔌 [CLIENT] Attempting to connect to server: $serverUrl');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      print('✅ [CLIENT] WebSocket channel created');
      print('🔧 [CLIENT] Setting up stream listener...');

      // Set up listener IMMEDIATELY to catch any early messages
      _channel!.stream.listen(
        (message) {
          // Always log that we received something (even before parsing)
          print('📥 [CLIENT] Raw message received (length: ${message.toString().length})');
          
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String?;
            
            // Always log that we received a message (but not full details for game_state)
            if (type == 'game_state') {
              // Just log that we got a game_state (detailed logging happens in callback)
              final tick = data['tick'] as int? ?? 0;
              if (tick % 60 == 0) {
                print('📥 [CLIENT] Received game_state (tick: $tick)');
              }
            } else {
              // Log ALL non-game_state messages prominently
              print('');
              print('═══════════════════════════════════════════════════════');
              print('📥 [CLIENT] ⭐ IMPORTANT: Received message type: $type');
              print('📥 [CLIENT] Raw message: ${message.toString()}');
              print('📥 [CLIENT] Parsed JSON: ${_formatJson(data)}');
              print('═══════════════════════════════════════════════════════');
              print('');
            }
            _handleMessage(data);
          } catch (e) {
            print('❌ [CLIENT] Error parsing message: $e');
            print('❌ [CLIENT] Raw message: ${message.toString()}');
          }
        },
        onError: (error) {
          print('❌ [CLIENT] WebSocket error: $error');
          _connected = false;
          onError?.call(error.toString());
        },
        onDone: () {
          print('🔌 [CLIENT] WebSocket connection closed');
          _connected = false;
          onDisconnected?.call();
        },
        cancelOnError: false, // Don't cancel on error, keep listening
      );

      print('✅ [CLIENT] Stream listener set up and active');

      // Wait a moment to ensure connection is fully established
      await Future.delayed(const Duration(milliseconds: 200));
      
      _connected = true;
      print('✅ [CLIENT] Successfully connected to server: $serverUrl');
      print('✅ [CLIENT] Connection status: $_connected');
      print('✅ [CLIENT] Channel status: ${_channel != null ? "exists" : "null"}');
      print('✅ [CLIENT] Ready to receive messages...');
      return true;
    } catch (e) {
      print('❌ [CLIENT] Failed to connect: $e');
      print('❌ [CLIENT] Server URL: $serverUrl');
      _connected = false;
      return false;
    }
  }
  
  /// Format JSON for readable logging
  String _formatJson(Map<String, dynamic> data) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) {
      print('⚠️ [CLIENT] Received message without type field');
      return;
    }

    print('🔄 [CLIENT] Handling message type: $type');
    switch (type) {
      case 'game_state':
        // Don't log game_state here - it's logged in the game callback
        onGameStateUpdate?.call(data);
        break;
      case 'arrow_spawned':
        print('');
        print('🏹🏹🏹 [CLIENT] ⭐ ARROW_SPAWNED EVENT RECEIVED! 🏹🏹🏹');
        print('   Arrow ID: ${data['arrow_id']}');
        print('   Position: (${data['start_x']}, ${data['start_y']})');
        print('   Angle: ${data['angle']}°');
        print('   Speed: ${data['speed']}');
        print('   Spawn Time: ${data['spawn_time']}');
        print('   Owner ID: ${data['owner_id']}');
        print('   Calling onArrowSpawned callback...');
        onArrowSpawned?.call(data);
        print('   ✅ Callback completed');
        print('');
        break;
      case 'hit_detected':
        print('');
        print('🎯🎯🎯 [CLIENT] ⭐ HIT_DETECTED EVENT RECEIVED! 🎯🎯🎯');
        print('   Arrow ID: ${data['arrow_id']}');
        print('   Body part: ${data['body_part']}');
        print('   Calling onHitDetected callback...');
        onHitDetected?.call(data);
        print('   ✅ Callback completed');
        print('');
        break;
      case 'player_joined':
        print('👤 [CLIENT] Player joined event received');
        onPlayerJoined?.call(data);
        break;
      case 'player_left':
        print('👋 [CLIENT] Player left event received');
        onPlayerLeft?.call(data);
        break;
      case 'room_joined':
        _playerId = data['player_id'] as String?;
        _roomId = data['room_id'] as String?;
        print('🚪 [CLIENT] Room joined successfully');
        print('   Player ID: $_playerId');
        print('   Room ID: $_roomId');
        break;
      default:
        print('⚠️ [CLIENT] Unknown message type: $type');
        print('   Full message: ${_formatJson(data)}');
    }
  }

  /// Join a game room
  void joinRoom(String roomId) {
    print('🚪 [CLIENT] Joining room: $roomId');
    _send({
      'type': 'join_room',
      'room_id': roomId,
    });
  }

  /// Send aim direction update to server
  void sendAimUpdate(Vector2 aimDirection) {
    print('🎯 [CLIENT] Sending aim update: (${aimDirection.x.toStringAsFixed(2)}, ${aimDirection.y.toStringAsFixed(2)})');
    _send({
      'type': 'aim_update',
      'aim_x': aimDirection.x,
      'aim_y': aimDirection.y,
    });
  }

  /// Send arrow shot event to server (with client-side prediction)
  void sendArrowShot({
    required Vector2 startPos,
    required double angleDeg,
    required double speed,
    required int clientTimestamp,
  }) {
    print('🏹 [CLIENT] Sending arrow shot event:');
    print('   Position: (${startPos.x.toStringAsFixed(2)}, ${startPos.y.toStringAsFixed(2)})');
    print('   Angle: ${angleDeg.toStringAsFixed(2)}°');
    print('   Speed: ${speed.toStringAsFixed(2)}');
    print('   Timestamp: $clientTimestamp');
    _send({
      'type': 'arrow_shot',
      'start_x': startPos.x,
      'start_y': startPos.y,
      'angle': angleDeg,
      'speed': speed,
      'timestamp': clientTimestamp,
    });
  }

  void _send(Map<String, dynamic> data) {
    if (!_connected || _channel == null) {
      print('❌ [CLIENT] Cannot send message: not connected');
      print('   Connection status: $_connected');
      print('   Channel: ${_channel != null ? "exists" : "null"}');
      return;
    }
    try {
      final jsonString = jsonEncode(data);
      print('📤 [CLIENT] Sending message:');
      print('   Type: ${data['type']}');
      print('   Full JSON: ${_formatJson(data)}');
      _channel!.sink.add(jsonString);
      print('✅ [CLIENT] Message sent successfully');
    } catch (e) {
      print('❌ [CLIENT] Error sending message: $e');
      print('   Message data: ${_formatJson(data)}');
    }
  }

  void disconnect() {
    print('🔌 [CLIENT] Disconnecting from server...');
    _connected = false;
    _channel?.sink.close();
    print('✅ [CLIENT] Disconnected');
  }

  bool get isConnected => _connected;
  String? get playerId => _playerId;
  String? get roomId => _roomId;
}

