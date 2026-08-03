import 'domino_engine.dart';

/// Moteur du Block Game (variante classique du dominos).
///
/// Règles :
/// - Aucune pioche (le bac n'est jamais utilisé).
/// - Un joueur qui ne peut pas jouer passe son tour.
/// - La partie se termine quand un joueur vide sa main, ou quand plus aucun
///   joueur ne peut jouer : le joueur avec le moins de points gagne.
class DominoBlockEngine extends DominoEngine {
  DominoBlockEngine({
    required super.human,
    super.isMultiplayer,
    super.roomCode,
    super.onStateChange,
    super.random,
  });

  @override
  String get variant => 'block';

  @override
  bool get canDraw => false;

  @override
  bool get canPass => currentPlayableTiles.isEmpty && !gameOver;

  @override
  DominoTile? drawFromBoneyard() => null;

  @override
  bool computeBlocked() {
    for (final p in players) {
      if (playableTilesFor(p).isNotEmpty) return false;
    }
    return true;
  }

  @override
  void aiTurn() {
    if (gameOver || currentPlayer.isHuman) return;

    final playable = currentPlayableTiles;
    if (playable.isEmpty) {
      if (canPass) passTurn();
      return;
    }

    final move = chooseAiMove(playable);
    playTile(move.$1, move.$2);
  }
}
