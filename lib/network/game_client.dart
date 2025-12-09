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
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _handleMessage(data);
          } catch (e) {
            print('Error parsing message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _connected = false;
          onError?.call(error.toString());
        },
        onDone: () {
          print('WebSocket closed');
          _connected = false;
          onDisconnected?.call();
        },
      );

      _connected = true;
      return true;
    } catch (e) {
      print('Failed to connect: $e');
      _connected = false;
      return false;
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'game_state':
        onGameStateUpdate?.call(data);
        break;
      case 'arrow_spawned':
        onArrowSpawned?.call(data);
        break;
      case 'hit_detected':
        onHitDetected?.call(data);
        break;
      case 'player_joined':
        onPlayerJoined?.call(data);
        break;
      case 'player_left':
        onPlayerLeft?.call(data);
        break;
      case 'room_joined':
        _playerId = data['player_id'] as String?;
        _roomId = data['room_id'] as String?;
        break;
      default:
        print('Unknown message type: $type');
    }
  }

  /// Join a game room
  void joinRoom(String roomId) {
    _send({
      'type': 'join_room',
      'room_id': roomId,
    });
  }

  /// Send aim direction update to server
  void sendAimUpdate(Vector2 aimDirection) {
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
      print('Cannot send: not connected');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  void disconnect() {
    _connected = false;
    _channel?.sink.close();
  }

  bool get isConnected => _connected;
  String? get playerId => _playerId;
  String? get roomId => _roomId;
}

