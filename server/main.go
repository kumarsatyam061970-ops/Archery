package main

import (
	"encoding/json"
	"log"
	"math"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins in development
	},
}

// GameServer manages all game rooms and connections
type GameServer struct {
	rooms    map[string]*GameRoom
	roomsMux sync.RWMutex
}

// GameRoom represents a game session
type GameRoom struct {
	id      string
	players map[string]*Player
	arrows  map[string]*Arrow
	tick    int
	mux     sync.RWMutex
}

// Player represents a connected player
type Player struct {
	id          string
	conn        *websocket.Conn
	position    Vector2
	aimDir      Vector2
	lastUpdate  int64
}

// Arrow represents a projectile in the game
type Arrow struct {
	id        string
	ownerId   string
	startPos  Vector2
	angle     float64
	speed     float64
	spawnTime int64
	active    bool
}

// Vector2 represents a 2D vector
type Vector2 struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

// Message represents a WebSocket message
type Message struct {
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data,omitempty"`
	Timestamp int64          `json:"timestamp,omitempty"`
}

// ArrowShotMessage represents an arrow shot event
type ArrowShotMessage struct {
	StartX    float64 `json:"start_x"`
	StartY    float64 `json:"start_y"`
	Angle     float64 `json:"angle"`
	Speed     float64 `json:"speed"`
	Timestamp int64   `json:"timestamp"`
}

// GameStateMessage represents the full game state
type GameStateMessage struct {
	Tick      int                    `json:"tick"`
	ServerTime float64               `json:"server_time"`
	Arrows    map[string]ArrowState  `json:"arrows"`
	Players   map[string]PlayerState `json:"players"`
}

// ArrowState represents arrow state for synchronization
type ArrowState struct {
	ID        string  `json:"id"`
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Angle     float64 `json:"angle"`
	Speed     float64 `json:"speed"`
	SpawnTime int64   `json:"spawn_time"`
	OwnerID   string  `json:"owner_id"`
}

// PlayerState represents player state for synchronization
type PlayerState struct {
	ID         string  `json:"id"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	AimX       float64 `json:"aim_x"`
	AimY       float64 `json:"aim_y"`
	LastUpdate int64   `json:"last_update"`
}

func NewGameServer() *GameServer {
	return &GameServer{
		rooms: make(map[string]*GameRoom),
	}
}

func (gs *GameServer) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	playerId := generatePlayerID()
	roomId := "room1" // Default room

	// Get or create room
	gs.roomsMux.Lock()
	room, exists := gs.rooms[roomId]
	if !exists {
		room = NewGameRoom(roomId)
		gs.rooms[roomId] = room
		go room.runGameLoop()
	}
	gs.roomsMux.Unlock()

	// Create player
	player := &Player{
		id:         playerId,
		conn:       conn,
		position:   Vector2{X: 25, Y: 350},
		aimDir:     Vector2{X: 1, Y: 0},
		lastUpdate: time.Now().UnixMilli(),
	}

	// Add player to room
	room.addPlayer(player)

	// Send room joined confirmation
	room.sendToPlayer(player, map[string]interface{}{
		"type":      "room_joined",
		"player_id": playerId,
		"room_id":   roomId,
	})

	// Handle incoming messages
	go func() {
		defer func() {
			room.removePlayer(playerId)
			conn.Close()
		}()

		for {
			var rawMsg map[string]interface{}
			err := conn.ReadJSON(&rawMsg)
			if err != nil {
				log.Printf("Read error: %v", err)
				break
			}

			room.handleMessage(player, rawMsg)
		}
	}()
}

func NewGameRoom(id string) *GameRoom {
	return &GameRoom{
		id:      id,
		players: make(map[string]*Player),
		arrows:  make(map[string]*Arrow),
		tick:    0,
	}
}

func (gr *GameRoom) addPlayer(player *Player) {
	gr.mux.Lock()
	defer gr.mux.Unlock()
	gr.players[player.id] = player
}

func (gr *GameRoom) removePlayer(playerId string) {
	gr.mux.Lock()
	defer gr.mux.Unlock()
	delete(gr.players, playerId)
}

func (gr *GameRoom) handleMessage(player *Player, rawMsg map[string]interface{}) {
	msgType, ok := rawMsg["type"].(string)
	if !ok {
		log.Printf("Invalid message: missing type")
		return
	}

	switch msgType {
	case "arrow_shot":
		// Parse arrow shot message directly from raw message
		arrowMsg := ArrowShotMessage{
			StartX:    getFloat64(rawMsg, "start_x"),
			StartY:    getFloat64(rawMsg, "start_y"),
			Angle:     getFloat64(rawMsg, "angle"),
			Speed:     getFloat64(rawMsg, "speed"),
			Timestamp: getInt64(rawMsg, "timestamp"),
		}
		gr.handleArrowShot(player, arrowMsg)

	case "aim_update":
		gr.mux.Lock()
		player.aimDir = Vector2{
			X: getFloat64(rawMsg, "aim_x"),
			Y: getFloat64(rawMsg, "aim_y"),
		}
		player.lastUpdate = time.Now().UnixMilli()
		gr.mux.Unlock()

	case "join_room":
		// Room joining is handled in handleWebSocket
		break
	}
}

// Helper functions to safely extract values from map
func getFloat64(m map[string]interface{}, key string) float64 {
	if val, ok := m[key]; ok {
		switch v := val.(type) {
		case float64:
			return v
		case int:
			return float64(v)
		case int64:
			return float64(v)
		}
	}
	return 0.0
}

func getInt64(m map[string]interface{}, key string) int64 {
	if val, ok := m[key]; ok {
		switch v := val.(type) {
		case int64:
			return v
		case int:
			return int64(v)
		case float64:
			return int64(v)
		}
	}
	return 0
}

func (gr *GameRoom) handleArrowShot(player *Player, msg ArrowShotMessage) {
	gr.mux.Lock()
	defer gr.mux.Unlock()

	// Create authoritative arrow
	arrowId := generateArrowID()
	arrow := &Arrow{
		id:        arrowId,
		ownerId:   player.id,
		startPos:  Vector2{X: msg.StartX, Y: msg.StartY},
		angle:     msg.Angle,
		speed:     msg.Speed,
		spawnTime: time.Now().UnixMilli(),
		active:    true,
	}

	gr.arrows[arrowId] = arrow

	// Broadcast arrow spawn to all players
	spawnMsg := map[string]interface{}{
		"type":       "arrow_spawned",
		"arrow_id":   arrowId,
		"start_x":    msg.StartX,
		"start_y":    msg.StartY,
		"angle":      msg.Angle,
		"speed":      msg.Speed,
		"spawn_time": arrow.spawnTime,
		"owner_id":   player.id,
	}

	gr.broadcast(spawnMsg)
}

func (gr *GameRoom) runGameLoop() {
	ticker := time.NewTicker(16 * time.Millisecond) // ~60 FPS
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			gr.update()
			gr.broadcastGameState()
		}
	}
}

func (gr *GameRoom) update() {
	gr.mux.Lock()
	defer gr.mux.Unlock()

	gr.tick++
	currentTime := time.Now().UnixMilli()
	gravity := 60.0

	// Update arrow positions (authoritative physics)
	for id, arrow := range gr.arrows {
		if !arrow.active {
			continue
		}

		// Calculate time since spawn
		elapsed := float64(currentTime-arrow.spawnTime) / 1000.0

		// Parabolic trajectory
		angleRad := arrow.angle * math.Pi / 180.0
		v0x := math.Cos(angleRad) * arrow.speed
		v0y := math.Sin(angleRad) * arrow.speed

		x := arrow.startPos.X + v0x*elapsed
		y := arrow.startPos.Y + v0y*elapsed + 0.5*gravity*elapsed*elapsed

		// Check collision with target (boy at x=425, y=350)
		if gr.checkCollision(Vector2{X: x, Y: y}, Vector2{X: 425, Y: 350}) {
			// Hit detected
			bodyPart := gr.determineBodyPart(Vector2{X: x, Y: y}, Vector2{X: 425, Y: 350})
			arrow.active = false

			// Broadcast hit
			hitMsg := map[string]interface{}{
				"type":      "hit_detected",
				"arrow_id":  id,
				"body_part": bodyPart,
				"position": map[string]float64{
					"x": x,
					"y": y,
				},
			}
			gr.broadcast(hitMsg)

			delete(gr.arrows, id)
		}

		// Remove arrows that are off-screen
		if x < -100 || x > 1000 || y < -100 || y > 1000 {
			arrow.active = false
			delete(gr.arrows, id)
		}
	}
}

func (gr *GameRoom) checkCollision(arrowPos, targetPos Vector2) bool {
	// Simple distance-based collision check
	// In a real game, you'd check against actual collider polygons
	dx := arrowPos.X - targetPos.X
	dy := arrowPos.Y - targetPos.Y
	distance := math.Sqrt(dx*dx + dy*dy)
	return distance < 50.0 // Collision radius
}

func (gr *GameRoom) determineBodyPart(arrowPos, targetPos Vector2) string {
	// Determine which body part was hit based on Y position
	dy := arrowPos.Y - targetPos.Y
	if dy < -30 {
		return "head"
	} else if dy < 20 {
		return "upperBody"
	} else {
		return "legs"
	}
}

func (gr *GameRoom) broadcastGameState() {
	gr.mux.RLock()
	defer gr.mux.RUnlock()

	// Build arrow states
	arrowStates := make(map[string]ArrowState)
	for id, arrow := range gr.arrows {
		if !arrow.active {
			continue
		}
		elapsed := float64(time.Now().UnixMilli()-arrow.spawnTime) / 1000.0
		angleRad := arrow.angle * math.Pi / 180.0
		v0x := math.Cos(angleRad) * arrow.speed
		v0y := math.Sin(angleRad) * arrow.speed
		gravity := 60.0

		x := arrow.startPos.X + v0x*elapsed
		y := arrow.startPos.Y + v0y*elapsed + 0.5*gravity*elapsed*elapsed

		arrowStates[id] = ArrowState{
			ID:        id,
			X:         x,
			Y:         y,
			Angle:     arrow.angle,
			Speed:     arrow.speed,
			SpawnTime: arrow.spawnTime,
			OwnerID:   arrow.ownerId,
		}
	}

	// Build player states
	playerStates := make(map[string]PlayerState)
	for id, player := range gr.players {
		playerStates[id] = PlayerState{
			ID:         id,
			X:          player.position.X,
			Y:          player.position.Y,
			AimX:       player.aimDir.X,
			AimY:       player.aimDir.Y,
			LastUpdate: player.lastUpdate,
		}
	}

	stateMsg := map[string]interface{}{
		"type":        "game_state",
		"tick":        gr.tick,
		"server_time": float64(time.Now().UnixMilli()) / 1000.0,
		"arrows":      arrowStates,
		"players":     playerStates,
	}

	gr.broadcast(stateMsg)
}

func (gr *GameRoom) broadcast(msg map[string]interface{}) {
	gr.mux.RLock()
	defer gr.mux.RUnlock()

	for _, player := range gr.players {
		gr.sendToPlayer(player, msg)
	}
}

func (gr *GameRoom) sendToPlayer(player *Player, msg map[string]interface{}) {
	if err := player.conn.WriteJSON(msg); err != nil {
		log.Printf("Error sending message to player %s: %v", player.id, err)
	}
}

func generatePlayerID() string {
	return "player_" + time.Now().Format("20060102150405") + "_" + randomString(6)
}

func generateArrowID() string {
	return "arrow_" + time.Now().Format("20060102150405") + "_" + randomString(6)
}

func randomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[time.Now().UnixNano()%int64(len(charset))]
	}
	return string(b)
}

func main() {
	server := NewGameServer()

	http.HandleFunc("/game", server.handleWebSocket)

	log.Println("Game server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

