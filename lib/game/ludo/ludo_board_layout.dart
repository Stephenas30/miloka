import 'package:flutter/material.dart';
import 'ludo_engine.dart';

/// Coordonnées sur une grille 15×15 pour le rendu du plateau.
class LudoBoardLayout {
  static const gridSize = 15;
  static const pathCoords = [
    [6, 13], [6, 12], [6, 11], [6, 10], [6, 9],
    [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
    [0, 7], [0, 6],
    [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
    [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0],
    [7, 0], [8, 0],
    [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
    [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6],
    [14, 7], [14, 8],
    [13, 8], [12, 8], [11, 8], [10, 8], [9, 8],
    [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14],
    [7, 14], [6, 14],
  ];

  static const homeStretchCoords = {
    LudoColor.red: [
      [7, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8],
    ],
    LudoColor.green: [
      [1, 7], [2, 7], [3, 7], [4, 7], [5, 7], [6, 7],
    ],
    LudoColor.yellow: [
      [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6],
    ],
    LudoColor.blue: [
      [13, 7], [12, 7], [11, 7], [10, 7], [9, 7], [8, 7],
    ],
  };

  static const baseCoords = {
    LudoColor.red: [
       [2, 11], [2, 12], [3, 11], [3, 12],
    ],
    LudoColor.green: [
      [2, 2], [2, 3], [3, 2], [3, 3],
    ],
    LudoColor.yellow: [
      [11, 2], [11, 3], [12, 2], [12, 3],
    ],
    LudoColor.blue: [
     [11, 11], [11, 12], [12, 11], [12, 12],
    ],
  };

  static const colorValues = {
    LudoColor.red: Color(0xFFE53935),
    LudoColor.green: Color(0xFF43A047),
    LudoColor.yellow: Color(0xFFFDD835),
    LudoColor.blue: Color(0xFF1E88E5),
  };

  static Offset pawnPosition(LudoPawn pawn, double cellSize) {
    if (pawn.finished) {
      return Offset(7.5 * cellSize, 7.5 * cellSize);
    }
    if (pawn.inHome) {
      final coords = homeStretchCoords[pawn.color]!;
      final homeIndex = pawn.stepsFromStart - 51;
      final c = coords[homeIndex.clamp(0, 5)];
      return Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize);
    }
    if (pawn.onTrack) {
      final c = pathCoords[pawn.trackIndex!];
      return Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize);
    }
    final bases = baseCoords[pawn.color]!;
    final c = bases[pawn.id];
    return Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize);
  }
}
