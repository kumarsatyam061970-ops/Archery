# Archery Multiplayer - Quick Start Guide

## Architecture Overview

```
Flutter (Flame) Client ──────▶ Go Backend
   - Aim UI                       - Authoritative physics
   - Input & prediction           - Game state & rooms
   - Local rendering              - Collision & hit validation
                                ◀──────────────
                     WebSocket real-time updates
```

## Setup Instructions

### 1. Start the Go Backend Server

```bash
cd server
go mod download
go run main.go
```

The server will start on `ws://localhost:8080/game`

### 2. Run the Flutter Client

```bash
flutter pub get
flutter run
```

## How It Works

### Client-Side (Flutter/Flame)

1. **Aim UI**: Visual aiming arrow that follows mouse/touch input
2. **Client-Side Prediction**: When you shoot, the arrow appears immediately (predicted)
3. **Local Rendering**: All visuals are rendered locally for smooth experience
4. **Reconciliation**: When server confirms arrow, client reconciles any differences

### Server-Side (Go)

1. **Authoritative Physics**: Server calculates all arrow trajectories
2. **Collision Detection**: Server validates all hits
3. **Game State**: Server maintains authoritative game state
4. **Broadcasting**: Server sends updates to all connected clients

## Features

- ✅ Real-time WebSocket communication
- ✅ Client-side prediction for instant feedback
- ✅ Server-side authoritative physics
- ✅ Collision detection and hit validation
- ✅ Multiplayer room support
- ✅ State synchronization

## Testing

1. Start the Go server
2. Run the Flutter app
3. Aim with mouse/touch
4. Press Space to shoot
5. Watch arrows fly and hit the target!

## Customization

- Change server URL in `lib/game/archery_game.dart` (line ~30)
- Adjust physics parameters (gravity, speed) in `ArcheryGame` class
- Modify collision detection in `server/main.go`

