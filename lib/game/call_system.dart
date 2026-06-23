import 'dart:math';
import 'dart:async';

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

class CallSystem {
  final List<String> players;
  int currentPlayerIndex = 0;

  List<CallOption> availableCalls = [
    CallOption.treble,
    CallOption.diamond,
    CallOption.heart,
    CallOption.spade,
    CallOption.sansAs,
    CallOption.toutAs,
    CallOption.x2,
    CallOption.x4,
    CallOption.pass,
  ];

  CallOption? highestCall;
  CallOption? contractCall;
  String? contractWinner;
  int passesInRow = 0;

  final List<CallOption> orderColors = [
    CallOption.treble,
    CallOption.diamond,
    CallOption.heart,
    CallOption.spade,
    CallOption.sansAs,
    CallOption.toutAs,
  ];

  CallSystem(this.players) {
    currentPlayerIndex = Random().nextInt(players.length);
    print("➡️ Premier joueur choisi aléatoirement : ${players[currentPlayerIndex]}");
    print("👉 C'est maintenant au tour de ${players[currentPlayerIndex]}");
  }

  String get currentPlayer => players[currentPlayerIndex];

  void nextTurn() {
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    print("👉 C'est maintenant au tour de ${players[currentPlayerIndex]}");
  }

  void setCurrentPlayer(String player) {
    final index = players.indexOf(player);
    if (index != -1) {
      currentPlayerIndex = index;
    }
  }

  Future<void> makeCall(CallOption option, {bool isHuman = false}) async {
    await Future.delayed(const Duration(seconds: 1));

    if (!availableCalls.contains(option)) {
      print("⛔ ${currentPlayer} ne peut pas appeler ${option.name}, ce n'est pas une option valide.");
      if (!isHuman) option = CallOption.pass;
      else return;
    }

    print("🎤 ${currentPlayer} a appelé : ${option.name}");

    if (option == CallOption.pass) {
      passesInRow++;
      if (highestCall == null ||
          highestCall == CallOption.treble ||
          highestCall == CallOption.sansAs) {
        // Trèfle et Sans As ne peuvent être passés qu'une fois : fin directe
        passesInRow = players.length;
      }
    } else {
      if (option == CallOption.x2 || option == CallOption.x4) {
        highestCall = option;
      } else {
        highestCall = option;
        contractCall = option;
        contractWinner = currentPlayer;
      }
      passesInRow = 0;

      // Mise à jour des appels disponibles
      if (orderColors.contains(option)) {
        final idx = orderColors.indexOf(option);
        availableCalls = orderColors.where((c) => orderColors.indexOf(c) > idx).toList()
          ..addAll([CallOption.x2, CallOption.x4, CallOption.pass]);
      } else if (option == CallOption.x2) {
        availableCalls = [CallOption.x4, CallOption.pass];
      } else if (option == CallOption.x4) {
        availableCalls = [CallOption.pass]; // plus rien au-dessus
      }
    }

    nextTurn();
  }

  bool isFinished() {
    if (highestCall != null && passesInRow >= players.length - 1) {
      print("✅ Tous les autres ont passé après ${highestCall!.name}");
      return true;
    }
    if (highestCall == null && passesInRow >= players.length) {
      print("❌ Tout le monde a passé, aucun appel retenu");
      return true;
    }
    return false;
  }

  Future<void> autoPlayTurn() async {
    if (isFinished()) return;

    if (currentPlayer == "Sud") {
      print("⏳ Attente du choix du joueur humain (Sud)");
      return; // Sud doit choisir via UI
    }

    final choice = availableCalls[Random().nextInt(availableCalls.length)];
    await makeCall(choice);

    if (!isFinished()) {
      await autoPlayTurn();
    }
  }
}
