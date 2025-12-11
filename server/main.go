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
	writeMux    sync.Mutex // Protects concurrent writes to WebSocket
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

// Polygon represents a collision shape with vertices
type Polygon struct {
	Vertices []Vector2
}

// CharacterBodyParts holds polygons for each body part
type CharacterBodyParts struct {
	Head      Polygon
	UpperBody Polygon
	LowerBody Polygon
}

// Character dimensions (should match client)
const (
	CharacterWidth  = 100.0
	CharacterHeight = 150.0
)

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
				log.Printf("❌ [SERVER] Read error from player %s: %v", playerId, err)
				break
			}

			log.Printf("📥 [SERVER] Received message from player %s: type=%v", playerId, rawMsg["type"])
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
		log.Printf("🏹 [SERVER] Received arrow_shot from player %s", player.id)
		// Parse arrow shot message directly from raw message
		arrowMsg := ArrowShotMessage{
			StartX:    getFloat64(rawMsg, "start_x"),
			StartY:    getFloat64(rawMsg, "start_y"),
			Angle:     getFloat64(rawMsg, "angle"),
			Speed:     getFloat64(rawMsg, "speed"),
			Timestamp: getInt64(rawMsg, "timestamp"),
		}
		log.Printf("🏹 [SERVER] Parsed arrow: pos=(%.2f, %.2f), angle=%.2f, speed=%.2f", 
			arrowMsg.StartX, arrowMsg.StartY, arrowMsg.Angle, arrowMsg.Speed)
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
	log.Printf("🏹 [SERVER] handleArrowShot called for player %s", player.id)

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

	// Hold lock only while modifying shared state
	gr.mux.Lock()
	gr.arrows[arrowId] = arrow
	arrowCount := len(gr.arrows)
	gr.mux.Unlock() // Release lock before broadcasting

	log.Printf("🏹 [SERVER] Created arrow %s, total arrows: %d", arrowId, arrowCount)

	// Broadcast arrow spawn to all players (this will acquire its own read lock)
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

	log.Printf("🏹 [SERVER] Broadcasting arrow_spawned to players")
	// Log the message content for debugging
	if jsonData, err := json.Marshal(spawnMsg); err == nil {
		log.Printf("🏹 [SERVER] Broadcast message content: %s", string(jsonData))
	}
	log.Printf("🏹 [SERVER] About to call gr.broadcast(spawnMsg)...")
	gr.broadcast(spawnMsg)
	log.Printf("🏹 [SERVER] Returned from gr.broadcast(spawnMsg)")
	log.Printf("🏹 [SERVER] Broadcast complete")
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

		// Check collision using polygon detection
		// Character position (should match client: origin.dx + 400, origin.dy)
		characterPos := Vector2{X: 425, Y: 350}
		arrowHeadPos := Vector2{X: x, Y: y} // Arrow head position
		
		hasCollision, bodyPart := gr.checkCollisionWithPolygons(arrowHeadPos, characterPos)
		if hasCollision {
			// Hit detected
			arrow.active = false

			// Broadcast hit with specific body part
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

// PointInPolygon checks if a point is inside a polygon using ray casting algorithm
func pointInPolygon(point Vector2, polygon Polygon) bool {
	if len(polygon.Vertices) < 3 {
		return false // Need at least 3 vertices for a polygon
	}

	inside := false
	j := len(polygon.Vertices) - 1

	for i := 0; i < len(polygon.Vertices); i++ {
		xi, yi := polygon.Vertices[i].X, polygon.Vertices[i].Y
		xj, yj := polygon.Vertices[j].X, polygon.Vertices[j].Y

		intersect := ((yi > point.Y) != (yj > point.Y)) &&
			(point.X < (xj-xi)*(point.Y-yi)/(yj-yi)+xi)

		if intersect {
			inside = !inside
		}
		j = i
	}

	return inside
}

// Initialize character body part polygons
func initCharacterBodyParts(characterPos Vector2) CharacterBodyParts {
	// Offset from character center
	cx := characterPos.X
	cy := characterPos.Y

	// Head polygon (top portion)
	headPolygon := Polygon{
		Vertices: []Vector2{
			{X: cx - CharacterWidth*0.3, Y: cy - CharacterHeight*0.5},      // Top-left
			{X: cx + CharacterWidth*0.3, Y: cy - CharacterHeight*0.5},      // Top-right
			{X: cx + CharacterWidth*0.4, Y: cy - CharacterHeight*0.3},      // Right-top
			{X: cx + CharacterWidth*0.35, Y: cy - CharacterHeight*0.1},     // Right-middle
			{X: cx - CharacterWidth*0.35, Y: cy - CharacterHeight*0.1},     // Left-middle
			{X: cx - CharacterWidth*0.4, Y: cy - CharacterHeight*0.3},      // Left-top
		},
	}

	// Upper body polygon (middle portion)
	upperBodyPolygon := Polygon{
		Vertices: []Vector2{
			{X: cx - CharacterWidth*0.35, Y: cy - CharacterHeight*0.1},      // Top-left
			{X: cx + CharacterWidth*0.35, Y: cy - CharacterHeight*0.1},      // Top-right
			{X: cx + CharacterWidth*0.4, Y: cy + CharacterHeight*0.2},        // Right-bottom
			{X: cx + CharacterWidth*0.3, Y: cy + CharacterHeight*0.25},      // Right-lower
			{X: cx - CharacterWidth*0.3, Y: cy + CharacterHeight*0.25},      // Left-lower
			{X: cx - CharacterWidth*0.4, Y: cy + CharacterHeight*0.2},       // Left-bottom
		},
	}

	// Lower body polygon (bottom portion)
	lowerBodyPolygon := Polygon{
		Vertices: []Vector2{
			{X: cx - CharacterWidth*0.3, Y: cy + CharacterHeight*0.25},       // Top-left
			{X: cx + CharacterWidth*0.3, Y: cy + CharacterHeight*0.25},       // Top-right
			{X: cx + CharacterWidth*0.35, Y: cy + CharacterHeight*0.5},      // Right-bottom
			{X: cx + CharacterWidth*0.25, Y: cy + CharacterHeight*0.5},      // Right-lower
			{X: cx - CharacterWidth*0.25, Y: cy + CharacterHeight*0.5},      // Left-lower
			{X: cx - CharacterWidth*0.35, Y: cy + CharacterHeight*0.5},      // Left-bottom
		},
	}

	return CharacterBodyParts{
		Head:      headPolygon,
		UpperBody: upperBodyPolygon,
		LowerBody: lowerBodyPolygon,
	}
}

// Check collision with character body parts using polygons
func (gr *GameRoom) checkCollisionWithPolygons(arrowPos Vector2, characterPos Vector2) (bool, string) {
	// Initialize character body parts
	bodyParts := initCharacterBodyParts(characterPos)

	// Check each body part polygon
	if pointInPolygon(arrowPos, bodyParts.Head) {
		return true, "head"
	}
	if pointInPolygon(arrowPos, bodyParts.UpperBody) {
		return true, "upperBody"
	}
	if pointInPolygon(arrowPos, bodyParts.LowerBody) {
		return true, "lowerBody"
	}

	return false, ""
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

	msgType, _ := msg["type"].(string)
	
	// Only log non-game_state messages to reduce spam (game_state is sent 60 times per second)
	if msgType != "game_state" {
		log.Printf("📢 [SERVER] Broadcasting %s message to %d players", msgType, len(gr.players))
	}
	
	for _, player := range gr.players {
		gr.sendToPlayer(player, msg)
	}
	
	if msgType != "game_state" {
		log.Printf("📢 [SERVER] Broadcast of %s complete", msgType)
	}
}

func (gr *GameRoom) sendToPlayer(player *Player, msg map[string]interface{}) {
	msgType, ok := msg["type"].(string)
	if !ok {
		msgType = "unknown"
	}
	
	// Protect WebSocket writes with mutex (WebSocket connections are not thread-safe)
	player.writeMux.Lock()
	defer player.writeMux.Unlock()
	
	// Only log non-game_state messages to reduce spam
	if msgType != "game_state" {
		log.Printf("📤 [SERVER] Sending message to player %s: type=%s", player.id, msgType)
	}
	
	// Set write deadline to prevent hanging
	player.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	
	if err := player.conn.WriteJSON(msg); err != nil {
		log.Printf("❌ [SERVER] Error sending message to player %s: %v", player.id, err)
	} else if msgType != "game_state" {
		log.Printf("✅ [SERVER] Successfully sent %s message to player %s", msgType, player.id)
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

