import 'dart:ui';

import 'fanorona_engine.dart';

/// Rendu du plateau Fanorona (5x9 points, 45 points).
///
/// Coordonnées: (colonne, rangée), rangée 0 = haut, rangée 4 = bas.
/// Position à l'écran: (col * cellSize, row * cellSize).
class FanoronaBoardLayout {
  static const Color humanColor = Color(0xFFFF8C00);
  static const Color aiColor = Color(0xFF9E9E9E);
  static const Color lineColor = Color(0xFFFFE0B2);
  static const Color strongPointColor = Color(0xFFFFCC80);

  /// Segments de lignes (start, end) en coordonnées de grille [col, row].
  static const List<List<int>> lineSegments = [
    // 5 horizontales
    [0, 0, 8, 0],
    [0, 1, 8, 1],
    [0, 2, 8, 2],
    [0, 3, 8, 3],
    [0, 4, 8, 4],
    // 9 verticales
    [0, 0, 0, 4],
    [1, 0, 1, 4],
    [2, 0, 2, 4],
    [3, 0, 3, 4],
    [4, 0, 4, 4],
    [5, 0, 5, 4],
    [6, 0, 6, 4],
    [7, 0, 7, 4],
    [8, 0, 8, 4],
    // 10 diagonales (motif en damier/tetrakis sur toute la largeur)
    // descente vers le bas-droite (col+, row+)
    [0, 0, 4, 4],
    [2, 0, 6, 4],
    [4, 0, 8, 4],
    [6, 0, 8, 2],
    [0, 2, 2, 4],
    // descente vers le bas-gauche (col-, row+)
    [0, 2, 2, 0],
    [0, 4, 4, 0],
    [2, 4, 6, 0],
    [4, 4, 8, 0],
    [6, 4, 8, 2],
  ];

  static Offset pointAt(int col, int row, double cellSize) =>
      Offset(col * cellSize, row * cellSize);

  static Offset pointAtIndex(int index, double cellSize) => pointAt(
    FanoronaEngine.colOf(index),
    FanoronaEngine.rowOf(index),
    cellSize,
  );

  static Size boardSize(double cellSize) =>
      Size((FanoronaEngine.cols - 1) * cellSize, (FanoronaEngine.rows - 1) * cellSize);

  /// Index de point le plus proche d'une position, ou -1 si trop loin.
  static int nearestPoint(Offset position, double cellSize) {
    final col = (position.dx / cellSize).round();
    final row = (position.dy / cellSize).round();
    if (col < 0 || col >= FanoronaEngine.cols) return -1;
    if (row < 0 || row >= FanoronaEngine.rows) return -1;
    final dist =
        (position - Offset(col * cellSize, row * cellSize)).distance;
    if (dist > cellSize * 0.6) return -1;
    return row * FanoronaEngine.cols + col;
  }

  /// Compte le nombre de points sur chaque ligne diagonale (vérification).
  static int diagonalLength(List<int> segment) {
    final dc = segment[2] - segment[0];
    return dc.abs() + 1; // == dr.abs() + 1
  }
}