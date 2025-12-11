import 'package:flame/components.dart';

/// Shared configuration for character body part polygons
/// These vertices should match the server definitions
class CharacterBodyPartConfig {
  // Character dimensions (should match sprite size)
  static const double characterWidth = 100.0;
  static const double characterHeight = 150.0; // Adjust based on aspect ratio

  /// Get head polygon vertices (relative to character center)
  /// Top portion of character
  static List<Vector2> getHeadVertices() {
    return [
      Vector2(-characterWidth * 0.3, -characterHeight * 0.5),   // Top-left
      Vector2(characterWidth * 0.3, -characterHeight * 0.5),   // Top-right
      Vector2(characterWidth * 0.4, -characterHeight * 0.3),   // Right-top
      Vector2(characterWidth * 0.35, -characterHeight * 0.1), // Right-middle
      Vector2(-characterWidth * 0.35, -characterHeight * 0.1), // Left-middle
      Vector2(-characterWidth * 0.4, -characterHeight * 0.3),  // Left-top
    ];
  }

  /// Get upper body polygon vertices (relative to character center)
  /// Middle portion of character
  static List<Vector2> getUpperBodyVertices() {
    return [
      Vector2(-characterWidth * 0.35, -characterHeight * 0.1),   // Top-left
      Vector2(characterWidth * 0.35, -characterHeight * 0.1),   // Top-right
      Vector2(characterWidth * 0.4, characterHeight * 0.2),    // Right-bottom
      Vector2(characterWidth * 0.3, characterHeight * 0.25),    // Right-lower
      Vector2(-characterWidth * 0.3, characterHeight * 0.25),   // Left-lower
      Vector2(-characterWidth * 0.4, characterHeight * 0.2),    // Left-bottom
    ];
  }

  /// Get lower body polygon vertices (relative to character center)
  /// Bottom portion of character
  static List<Vector2> getLowerBodyVertices() {
    return [
      Vector2(-characterWidth * 0.3, characterHeight * 0.25),   // Top-left
      Vector2(characterWidth * 0.3, characterHeight * 0.25),    // Top-right
      Vector2(characterWidth * 0.35, characterHeight * 0.5),    // Right-bottom
      Vector2(characterWidth * 0.25, characterHeight * 0.5),   // Right-lower
      Vector2(-characterWidth * 0.25, characterHeight * 0.5),   // Left-lower
      Vector2(-characterWidth * 0.35, characterHeight * 0.5),   // Left-bottom
    ];
  }
}

