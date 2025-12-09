# Archery Game Server

Go backend server for the multiplayer archery game.

## Setup

1. Install Go (1.21 or later)
2. Install dependencies:
   ```bash
   go mod download
   ```
3. Run the server:
   ```bash
   go run main.go
   ```

The server will start on `ws://localhost:8080/game`

## Features

- WebSocket real-time communication
- Authoritative physics simulation
- Collision detection and hit validation
- Game state synchronization
- Room-based multiplayer support

## Message Protocol

### Client → Server

**Arrow Shot:**
```json
{
  "type": "arrow_shot",
  "data": {
    "start_x": 25.0,
    "start_y": 350.0,
    "angle": 330.0,
    "speed": 300.0,
    "timestamp": 1234567890
  }
}
```

**Aim Update:**
```json
{
  "type": "aim_update",
  "data": {
    "aim_x": 1.0,
    "aim_y": 0.0
  }
}
```

### Server → Client

**Arrow Spawned:**
```json
{
  "type": "arrow_spawned",
  "arrow_id": "arrow_123",
  "start_x": 25.0,
  "start_y": 350.0,
  "angle": 330.0,
  "speed": 300.0,
  "spawn_time": 1234567890,
  "owner_id": "player_123"
}
```

**Hit Detected:**
```json
{
  "type": "hit_detected",
  "arrow_id": "arrow_123",
  "body_part": "head",
  "position": {"x": 425.0, "y": 350.0}
}
```

**Game State:**
```json
{
  "type": "game_state",
  "tick": 1000,
  "server_time": 1234567.89,
  "arrows": {...},
  "players": {...}
}
```

