import 'dart:math';

class CallSystem {
  final List<String> players; // ["Nord", "Est", "Sud", "Ouest"]
  final List<Call> calls = [];
  int currentPlayerIndex = 0;

  CallSystem(this.players) {
    // Choisir aléatoirement qui commence
    currentPlayerIndex = Random().nextInt(players.length);
  }

  String get currentPlayer => players[currentPlayerIndex];

  void nextTurn() {
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
  }

  void makeCall(CallOption option) {
    calls.add(Call(currentPlayer, option));
    nextTurn();
  }

  bool isFinished() {
    // Simplifié : fini si tout le monde a passé
    return calls.length >= players.length &&
        calls.every((c) => c.option == CallOption.pass);
  }
}

enum CallOption {
  treble,   // Trèfle
  diamond,  // Carreau
  heart,    // Coeur
  spade,    // Pique
  sansAs,   // Sans As
  toutAs,   // Tout As
  x2,
  x4,
  pass,
}

class Call {
  final String playerName;
  final CallOption option;

  Call(this.playerName, this.option);
}
