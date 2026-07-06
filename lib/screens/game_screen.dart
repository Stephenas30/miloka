import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math';
import '../game/deck.dart';
import '../models/card_model.dart';
import '../game/call_system.dart';
import '../widgets/call_popup.dart';
import '../service/stats_service.dart';

class PlayedCard {
  final String player;
  final CardModel card;
  PlayedCard(this.player, this.card);
}

class HandHistoryEntry {
  final CallOption contractCall;
  final String contractWinner;
  final String winningTeam;
  final Map<String, int> delta;
  final bool dedans;

  HandHistoryEntry({
    required this.contractCall,
    required this.contractWinner,
    required this.winningTeam,
    required this.delta,
    required this.dedans,
  });
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
  with SingleTickerProviderStateMixin {
  late Deck deck;
  late CallSystem callSystem;

  List<CardModel> playerHand = [];
  List<List<CardModel>> aiHands = [[], [], []]; // Nord, Est, Ouest

  bool showCallBubble = false;
  String callBubblePlayer = "";
  String callBubbleText = "";
  bool biddingFinished = false;
  bool gameStarted = false;
  bool gameOver = false;
  String? starterPlayer;
  String? winningPlayer;
  int tricksPlayed = 0;
  List<PlayedCard> currentTrick = [];
  Map<String, int> teamPoints = {"NS": 0, "EO": 0};
  Map<String, int> gameScore = {"NS": 0, "EO": 0}; // Score global du jeu
  bool waitingForNextHand = false;
  Map<String, int> lastHandDelta = {"NS": 0, "EO": 0};
  List<HandHistoryEntry> handHistory = [];
  String? overallWinner;
  int starterIndex = 0;

  CardModel? animatingDealCard;
  String? animatingDealPlayer;
  bool dealCardAtTarget = false;
  CardModel? animatingPlayCard;
  String? animatingPlayPlayer;
  bool playCardAtCenter = false;
  final Duration dealAnimationDuration = const Duration(milliseconds: 500);
  final Duration playAnimationDuration = const Duration(milliseconds: 450);

  late List<String> order; // ordre de distribution
  final List<String> players = ["Nord", "Est", "Sud", "Ouest"];

  @override
  void initState() {
    super.initState();
    deck = Deck();
    deck.shuffle();

    // Choisir aléatoirement le joueur qui commence AU DÉBUT de la partie
    starterIndex = Random().nextInt(players.length);
    order = [for (int i = 0; i < players.length; i++) players[(starterIndex + i) % players.length]];
    callSystem = CallSystem(players, initialIndex: starterIndex);

    // Lancer la distribution animée
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dealCards();
    });
  }

  /// Distribution animée : 3 cartes chacun puis 2 cartes chacun
  Future<void> _dealCards() async {
    // Premier tour : 3 cartes chacun
    for (var player in order) {
      for (var i = 0; i < 3; i++) {
        await _dealCardToPlayer(player);
      }
    }

    // Deuxième tour : 2 cartes chacun
    for (var player in order) {
      for (var i = 0; i < 2; i++) {
        await _dealCardToPlayer(player);
      }
    }

    // Quand la distribution est terminée → lancer le popup d’appel
    await _showCallPopup();
  }

  Future<void> _dealCardToPlayer(String player) async {
    final card = deck.deal(1).first;
    setState(() {
      animatingDealCard = card;
      animatingDealPlayer = player;
      dealCardAtTarget = false;
    });

    await Future.delayed(const Duration(milliseconds: 20));
    setState(() {
      dealCardAtTarget = true;
    });
    await Future.delayed(dealAnimationDuration + const Duration(milliseconds: 50));

    setState(() {
      if (player == "Nord") {
        aiHands[0].add(card);
      } else if (player == "Est") {
        aiHands[1].add(card);
      } else if (player == "Ouest") {
        aiHands[2].add(card);
      } else {
        playerHand.add(card);
      }
      animatingDealCard = null;
      animatingDealPlayer = null;
      dealCardAtTarget = false;
    });
  }

  void _giveCards(String player, int count) {
    if (player == "Nord") {
      aiHands[0].addAll(deck.deal(count));
    } else if (player == "Est") {
      aiHands[1].addAll(deck.deal(count));
    } else if (player == "Ouest") {
      aiHands[2].addAll(deck.deal(count));
    } else if (player == "Sud") {
      playerHand.addAll(deck.deal(count));
    }
  }

  List<CardModel> _handForPlayer(String player) {
    switch (player) {
      case "Nord":
        return aiHands[0];
      case "Est":
        return aiHands[1];
      case "Ouest":
        return aiHands[2];
      default:
        return playerHand;
    }
  }

  CallOption _bestCallForPlayer(String player) {
    final hand = _handForPlayer(player);
    final counts = <Suit, int>{
      Suit.trefle: 0,
      Suit.carreau: 0,
      Suit.coeur: 0,
      Suit.pique: 0,
    };

    for (final card in hand) {
      counts[card.suit] = counts[card.suit]! + 1;
    }

    final sortedSuits = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedSuits) {
      final option = _suitToCallOption(entry.key);
      if (callSystem.availableCalls.contains(option)) {
        return option;
      }
    }

    return CallOption.pass;
  }

  CallOption _suitToCallOption(Suit suit) {
    switch (suit) {
      case Suit.trefle:
        return CallOption.treble;
      case Suit.carreau:
        return CallOption.diamond;
      case Suit.coeur:
        return CallOption.heart;
      case Suit.pique:
        return CallOption.spade;
    }
  }

  String _callOptionLabel(CallOption option) {
    switch (option) {
      case CallOption.treble:
        return "Trèfle";
      case CallOption.diamond:
        return "Carreau";
      case CallOption.heart:
        return "Cœur";
      case CallOption.spade:
        return "Pique";
      case CallOption.sansAs:
        return "Sans As";
      case CallOption.toutAs:
        return "Tout As";
      case CallOption.x2:
        return "x2";
      case CallOption.x4:
        return "x4";
      case CallOption.pass:
        return "Passer";
    }
  }

  int _rankValue(Rank rank, CallOption mode) {
    switch (mode) {
      case CallOption.sansAs:
        switch (rank) {
          case Rank.as:
            return 800;
          case Rank.dix:
            return 700;
          case Rank.roi:
            return 600;
          case Rank.dame:
            return 500;
          case Rank.valet:
            return 400;
          case Rank.neuf:
            return 300;
          case Rank.huit:
            return 200;
          case Rank.sept:
            return 100;
        }
      case CallOption.toutAs:
      default:
        switch (rank) {
          case Rank.valet:
            return 800;
          case Rank.neuf:
            return 700;
          case Rank.as:
            return 600;
          case Rank.dix:
            return 500;
          case Rank.roi:
            return 400;
          case Rank.dame:
            return 300;
          case Rank.huit:
            return 200;
          case Rank.sept:
            return 100;
        }
    }
  }

  List<CardModel> _sortedSouthHand(CallOption? contractCall) {
    final cards = List<CardModel>.from(playerHand);
    Suit? calledSuit;
    if (contractCall == CallOption.treble) calledSuit = Suit.trefle;
    if (contractCall == CallOption.diamond) calledSuit = Suit.carreau;
    if (contractCall == CallOption.heart) calledSuit = Suit.coeur;
    if (contractCall == CallOption.spade) calledSuit = Suit.pique;

    final defaultMode = contractCall == CallOption.sansAs
        ? CallOption.sansAs
        : contractCall == CallOption.toutAs
        ? CallOption.toutAs
        : CallOption.sansAs;

    final suitOrder = <Suit>[];
    if (calledSuit != null) {
      suitOrder.add(calledSuit);
      for (var suit in Suit.values) {
        if (suit != calledSuit) suitOrder.add(suit);
      }
    } else {
      suitOrder.addAll(Suit.values);
    }

    cards.sort((a, b) {
      final aGroup = suitOrder.indexOf(a.suit);
      final bGroup = suitOrder.indexOf(b.suit);
      if (aGroup != bGroup) return aGroup.compareTo(bGroup);

      final aMode = calledSuit != null && a.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      final bMode = calledSuit != null && b.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      return _rankValue(b.rank, bMode).compareTo(_rankValue(a.rank, aMode));
    });

    return cards;
  }

  Suit? _contractTrumpSuit() {
    final contract = callSystem.contractCall;
    switch (contract) {
      case CallOption.treble:
        return Suit.trefle;
      case CallOption.diamond:
        return Suit.carreau;
      case CallOption.heart:
        return Suit.coeur;
      case CallOption.spade:
        return Suit.pique;
      default:
        return null;
    }
  }

  bool _isTrump(CardModel card) {
    if (callSystem.contractCall == CallOption.toutAs) return true;
    if (callSystem.contractCall == CallOption.sansAs) return false;
    final trumpSuit = _contractTrumpSuit();
    return card.suit == trumpSuit;
  }

  int _trickCardStrength(CardModel card, Suit? leadSuit) {
    if (leadSuit == null) {
      return _rankValue(card.rank, CallOption.toutAs);
    }
    final contract = callSystem.contractCall;
    final cardIsLead = card.suit == leadSuit;
    final trumpSuit = _contractTrumpSuit();
    final cardIsTrump = _isTrump(card);
    final leadIsTrump = leadSuit == trumpSuit;

    const int trumpBase = 2000; // any trump must beat any non-trump
    const int leadBase = 1000; // base for following the lead

    if (contract == CallOption.toutAs) {
      if (!cardIsLead) return 0;
      return leadBase + _rankValue(card.rank, CallOption.toutAs);
    }

    if (contract == CallOption.sansAs) {
      if (!cardIsLead) return 0;
      return leadBase + _rankValue(card.rank, CallOption.sansAs);
    }

    // If the trick was led with the trump suit, only trumps can win
    if (leadIsTrump) {
      if (!cardIsTrump) return 0;
      return trumpBase + _rankValue(card.rank, CallOption.toutAs);
    }

    // Any trump beats all non-trump cards
    if (cardIsTrump) {
      return trumpBase + _rankValue(card.rank, CallOption.toutAs);
    }

    if (cardIsLead) {
      return leadBase + _rankValue(card.rank, CallOption.sansAs);
    }

    return 0;
  }

  int _cardPointValue(CardModel card) {
    final contract = callSystem.contractCall;
    final rank = card.rank;
    if (contract == CallOption.sansAs) {
      switch (rank) {
        case Rank.as:
          return 11;
        case Rank.dix:
          return 10;
        case Rank.roi:
          return 4;
        case Rank.dame:
          return 3;
        case Rank.valet:
          return 2;
        case Rank.neuf:
        case Rank.huit:
        case Rank.sept:
          return 0;
      }
    }
    if (_isTrump(card)) {
      switch (rank) {
        case Rank.as:
          return 11;
        case Rank.dix:
          return 10;
        case Rank.roi:
          return 4;
        case Rank.dame:
          return 3;
        case Rank.valet:
          return 20;
        case Rank.neuf:
          return 14;
        case Rank.huit:
        case Rank.sept:
          return 0;
      }
    }
    switch (rank) {
      case Rank.as:
        return 11;
      case Rank.dix:
        return 10;
      case Rank.roi:
        return 4;
      case Rank.dame:
        return 3;
      case Rank.valet:
        return 2;
      case Rank.neuf:
      case Rank.huit:
      case Rank.sept:
        return 0;
    }
  }

  String _teamOf(String player) {
    return player == "Nord" || player == "Sud" ? "NS" : "EO";
  }

  String _handWinningTeam() {
    final preneur = callSystem.contractWinner;
    if (preneur == null) return "NS";
    final preneurTeam = _teamOf(preneur);
    final defenseTeam = preneurTeam == "NS" ? "EO" : "NS";
    final preneurPoints = teamPoints[preneurTeam] ?? 0;
    final defensePoints = teamPoints[defenseTeam] ?? 0;

    if (preneurPoints > defensePoints) {
      return preneurTeam;
    }
    return defenseTeam;
  }

  void _registerLastHandHistory() {
    final contract = callSystem.contractCall;
    final preneur = callSystem.contractWinner;
    if (contract == null || preneur == null) return;
    final preneurTeam = _teamOf(preneur);
    final winnerTeam = _handWinningTeam();
    final dedans = winnerTeam != preneurTeam;

    handHistory.add(HandHistoryEntry(
      contractCall: contract,
      contractWinner: preneur,
      winningTeam: winnerTeam,
      delta: Map<String, int>.from(lastHandDelta),
      dedans: dedans,
    ));
  }

  void _showStatistics() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Statistiques de la partie'),
        content: SizedBox(
          width: double.maxFinite,
          child: handHistory.isEmpty
              ? const Text('Aucune manche jouée pour cette partie.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: handHistory.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final entry = handHistory[index];
                    final contractLabel = _callOptionLabel(entry.contractCall);
                    final isDedans = entry.dedans ? 'Oui' : 'Non';
                    final winnerLabel = entry.winningTeam == 'NS' ? 'Nord-Sud' : 'Est-Ouest';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manche ${index + 1}: $winnerLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Contrat: $contractLabel'),
                        Text('Preneur: ${entry.contractWinner}'),
                        Text('Dedans: $isDedans'),
                        Text('Score: NS ${entry.delta['NS']} / EO ${entry.delta['EO']}'),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  List<CardModel> _handFor(String player) {
    if (player == "Nord") return aiHands[0];
    if (player == "Est") return aiHands[1];
    if (player == "Ouest") return aiHands[2];
    return playerHand;
  }

  CallOption _playModeForSuit(Suit leadSuit) {
    if (callSystem.contractCall == CallOption.toutAs) return CallOption.toutAs;
    if (callSystem.contractCall == CallOption.sansAs) return CallOption.sansAs;
    final trumpSuit = _contractTrumpSuit();
    if (leadSuit == trumpSuit) return CallOption.toutAs;
    return CallOption.sansAs;
  }

  List<CardModel> _legalCards(String player) {
    final hand = _handFor(player);
    if (currentTrick.isEmpty) return hand;
    final leadSuit = currentTrick.first.card.suit;
    
    // Check if player has cards of the lead suit
    final leadCards = hand.where((card) => card.suit == leadSuit).toList();
    if (leadCards.isNotEmpty) {
      // Player must follow suit.
      
      // Check if we should apply the "must play stronger card" rule
      // This only applies for: ToutAs contracts OR when playing trump cards in a color contract
      final isToutAsContract = callSystem.contractCall == CallOption.toutAs;
      final isTrumpSuit = _contractTrumpSuit() == leadSuit && 
          callSystem.contractCall != CallOption.sansAs;
      final shouldApplySurtrumpRule = isToutAsContract || isTrumpSuit;

      if (shouldApplySurtrumpRule) {
        // If a stronger card of the same suit is already on the table,
        // player must play a stronger card if they have one.
        final cardsOfLeadSuitOnTable = currentTrick
            .where((played) => played.card.suit == leadSuit)
            .map((played) => played.card)
            .toList();

        if (cardsOfLeadSuitOnTable.isNotEmpty) {
          // Find the strongest card of the lead suit currently on the table
          final strongestOnTable = cardsOfLeadSuitOnTable
              .map((c) => _trickCardStrength(c, leadSuit))
              .reduce(max);

          // Find player's cards of the lead suit that are stronger than the strongest on table
          final strongerCards = leadCards
              .where((card) => _trickCardStrength(card, leadSuit) > strongestOnTable)
              .toList();

          // If player has stronger cards, they must play one
          if (strongerCards.isNotEmpty) {
            return strongerCards;
          }
        }
      }

      // Player can play any card of the lead suit
      return leadCards;
    }
    
    // If no one followed the lead, player must cut with a trump if possible.
    // This is the contract couleur rule: if a player has no card of the lead suit,
    // they must play an atout. If multiple players cut, the strongest atout
    // according to the "ToutAs" scale wins the trick.
    final isTrumpContract = callSystem.contractCall == CallOption.treble ||
        callSystem.contractCall == CallOption.diamond ||
        callSystem.contractCall == CallOption.heart ||
        callSystem.contractCall == CallOption.spade ||
        callSystem.contractCall == CallOption.toutAs;

    if (isTrumpContract) {
      final trumps = hand.where(_isTrump).toList();
      if (trumps.isEmpty) return hand;

      // Find trumps already played in this trick
      final trumpsOnTable = currentTrick
          .where((played) => _isTrump(played.card))
          .map((played) => played.card)
          .toList();

      if (trumpsOnTable.isNotEmpty) {
        // Highest trump currently on table (by rank value under trump rules)
        final highestOnTable = trumpsOnTable
            .map((c) => _rankValue(c.rank, CallOption.toutAs))
            .reduce(max);

        // Player's trumps that are strictly higher than the highest on table
        final higherTrumps = trumps
            .where((c) => _rankValue(c.rank, CallOption.toutAs) > highestOnTable)
            .toList();

        if (higherTrumps.isNotEmpty) {
          // Must overtrump if possible
          return higherTrumps;
        }

        // Cannot overtrump but has trumps → may play any trump
        return trumps;
      }

      // No trumps on table yet → must play a trump if possible
      return trumps;
    }

    return hand;
  }

  PlayedCard _currentWinningCard() {
    final leadSuit = currentTrick.first.card.suit;
    PlayedCard winner = currentTrick.first;
    for (final played in currentTrick.skip(1)) {
      if (_trickCardStrength(played.card, leadSuit) >
          _trickCardStrength(winner.card, leadSuit)) {
        winner = played;
      }
    }
    return winner;
  }

  bool _isPartnerWinning(String player) {
    final winner = _currentWinningCard();
    return _teamOf(winner.player) == _teamOf(player) && winner.player != player;
  }

  CardModel _lowestPointCard(List<CardModel> candidates) {
    candidates.sort((a, b) {
      final aPoint = _cardPointValue(a);
      final bPoint = _cardPointValue(b);
      if (aPoint != bPoint) return aPoint.compareTo(bPoint);
      return _trickCardStrength(a, currentTrick.first.card.suit)
          .compareTo(_trickCardStrength(b, currentTrick.first.card.suit));
    });
    return candidates.first;
  }

  CardModel _minimalWinningCard(List<CardModel> candidates, Suit leadSuit) {
    candidates.sort((a, b) {
      final aStrength = _trickCardStrength(a, leadSuit);
      final bStrength = _trickCardStrength(b, leadSuit);
      if (aStrength != bStrength) return aStrength.compareTo(bStrength);
      return _cardPointValue(a).compareTo(_cardPointValue(b));
    });
    return candidates.first;
  }

  CardModel _pickLeadCard(String player) {
    final hand = _handFor(player);
    hand.sort((a, b) {
      final aStrength = _trickCardStrength(a, null);
      final bStrength = _trickCardStrength(b, null);
      if (aStrength != bStrength) return bStrength.compareTo(aStrength);
      return _cardPointValue(b).compareTo(_cardPointValue(a));
    });
    return hand.first;
  }

  String _nextPlayer(String current) {
    final index = players.indexOf(current);
    return players[(index + 1) % players.length];
  }

  void _startGame() {
    if (callSystem.contractWinner != null) {
      print("🎬 Début de la manche. Preneur : ${callSystem.contractWinner}");
      callSystem.setCurrentPlayer(callSystem.contractWinner!);
      setState(() {
        gameStarted = true;
        gameOver = false;
      });
      print("👉 Premier joueur de la manche : ${callSystem.currentPlayer}");
    }
  }

  void _resolveTrick() {
    final leadSuit = currentTrick.first.card.suit;
    PlayedCard winner = currentTrick.first;
    for (final played in currentTrick) {
      final currentStrength = _trickCardStrength(played.card, leadSuit);
      final winnerStrength = _trickCardStrength(winner.card, leadSuit);
      if (currentStrength > winnerStrength) {
        winner = played;
      }
    }
    final trickPoints = currentTrick.fold(
      0,
      (sum, played) => sum + _cardPointValue(played.card),
    );
    final team = _teamOf(winner.player);
    teamPoints[team] = teamPoints[team]! + trickPoints;
    tricksPlayed += 1;
    final nextLeader = winner.player;
    setState(() {
      currentTrick = [];
      callSystem.setCurrentPlayer(nextLeader);
      if (tricksPlayed >= 8) {
        gameOver = true;
        gameStarted = false;
        // Calculer le score de la manche mais ne pas l'appliquer tant que l'utilisateur n'appuie pas sur "Suivant"
        lastHandDelta = _computeHandScores();
        _registerLastHandHistory();
        waitingForNextHand = true;
      }
    });
    print("🏆 Gagnant du pli : $nextLeader (+$trickPoints pts pour $team)");
    if (!gameOver && nextLeader != "Sud") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAITurn();
      });
    }
  }

  Map<String, int> _computeHandScores() {
    final result = {"NS": 0, "EO": 0};
    final contract = callSystem.contractCall;
    final preneur = callSystem.contractWinner;
    if (contract == null || preneur == null) return result;

    final preneurTeam = _teamOf(preneur);
    final defenseTeam = preneurTeam == "NS" ? "EO" : "NS";
    final preneurPoints = teamPoints[preneurTeam] ?? 0;
    final defensePoints = teamPoints[defenseTeam] ?? 0;
    final isX2 = callSystem.highestCall == CallOption.x2;
    final isX4 = callSystem.highestCall == CallOption.x4;
    final multiplier = isX4 ? 4 : isX2 ? 2 : 1;

    void award(String team, int pts) {
      result[team] = (result[team] ?? 0) + pts;
    }

    if (contract == CallOption.sansAs) {
      if (preneurPoints > defensePoints) {
        if (defensePoints == 0) {
          award(preneurTeam, 70 * multiplier);
        } else {
          award(preneurTeam, 52 * multiplier);
        }
      } else {
        if (preneurPoints == 0) {
          award(defenseTeam, 90 * multiplier);
        } else {
          award(defenseTeam, 52 * multiplier);
        }
      }
      return result;
    }

    if (contract == CallOption.treble) {
      if (preneurPoints > defensePoints) {
        if (defensePoints == 0) {
          award(preneurTeam, isX2 ? 90 : isX4 ? 180 : 45);
        } else {
          award(preneurTeam, isX2 ? 64 : isX4 ? 128 : 32);
        }
      } else {
        if (preneurPoints == 0) {
          award(defenseTeam, isX2 ? 128 : isX4 ? 256 : 90);
        } else {
          award(defenseTeam, isX2 ? 64 : isX4 ? 128 : 32);
        }
      }
      return result;
    }

    if (contract == CallOption.diamond || contract == CallOption.heart || contract == CallOption.spade) {
      if (preneurPoints > defensePoints) {
        if (defensePoints == 0) {
          award(preneurTeam, isX2 ? 75 : isX4 ? 150 : 45);
        } else {
          award(preneurTeam, isX2 ? 32 : isX4 ? 64 : 16);
        }
      } else {
        if (preneurPoints == 0) {
          award(defenseTeam, isX2 ? 75 : isX4 ? 150 : 45);
        } else {
          award(defenseTeam, isX2 ? 32 : isX4 ? 64 : 16);
        }
      }
      return result;
    }

    if (contract == CallOption.toutAs) {
      if (preneurPoints == 134 && defensePoints == 124) {
        return result;
      }
      if (defensePoints > 124) {
        award(defenseTeam, 26 * multiplier);
        return result;
      }
      if (preneurPoints > 164) {
        award(preneurTeam, 26 * multiplier);
        return result;
      }
      if (defensePoints == 0) {
        award(preneurTeam, isX2 ? 70 : isX4 ? 104 : 35);
        return result;
      }
      if (preneurPoints == 0) {
        award(defenseTeam, isX2 ? 90 : isX4 ? 104 : 45);
        return result;
      }
      int p = (preneurPoints / 10).round();
      if (p < 14) p = 14;
      if (p > 16) p = 16;
      award(preneurTeam, p * multiplier);
      award(defenseTeam, (26 - p) * multiplier);
      return result;
    }

    return result;
  }

  void _applyLastHandAndNext() {
    bool shouldStartNextHand = true;

    setState(() {
      gameScore["NS"] = gameScore["NS"]! + (lastHandDelta["NS"] ?? 0);
      gameScore["EO"] = gameScore["EO"]! + (lastHandDelta["EO"] ?? 0);

      // Vérifier condition de victoire (150 points)
      if (gameScore["NS"]! >= 150 || gameScore["EO"]! >= 150) {
        overallWinner = gameScore["NS"]! >= 150 ? "NS" : "EO";
        waitingForNextHand = false;
        shouldStartNextHand = false;
      }

      if (overallWinner == null) {
        // Reset pour la manche suivante
        waitingForNextHand = false;
        lastHandDelta = {"NS": 0, "EO": 0};
        teamPoints = {"NS": 0, "EO": 0};
        tricksPlayed = 0;
        currentTrick = [];
        playerHand.clear();
        aiHands = [[], [], []];
        deck = Deck();
        deck.shuffle();
        // Le premier joueur de la nouvelle manche suit l'ordre horaire
        starterIndex = (starterIndex + 1) % players.length;
        order = [for (int i = 0; i < players.length; i++) players[(starterIndex + i) % players.length]];
        callSystem = CallSystem(players, initialIndex: starterIndex);
        biddingFinished = false;
        gameOver = false;
      }
    });

    if (shouldStartNextHand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dealCards();
      });
    }
  }

  Future<void> _playCard(String player, CardModel card) async {
    print("🃏 $player joue ${card.assetPath}");
    final hand = _handFor(player);
    setState(() {
      hand.remove(card);
      animatingPlayCard = card;
      animatingPlayPlayer = player;
      playCardAtCenter = false;
    });

    await Future.delayed(const Duration(milliseconds: 20));
    setState(() {
      playCardAtCenter = true;
    });
    await Future.delayed(playAnimationDuration + const Duration(milliseconds: 50));

    setState(() {
      currentTrick.add(PlayedCard(player, card));
      animatingPlayCard = null;
      animatingPlayPlayer = null;
      playCardAtCenter = false;
    });

    if (currentTrick.length >= 4) {
      await Future.delayed(const Duration(milliseconds: 400));
      _resolveTrick();
    } else {
      final next = _nextPlayer(player);
      print("➡️ Prochain joueur : $next");
      callSystem.setCurrentPlayer(next);
      if (next != "Sud") {
        await Future.delayed(const Duration(milliseconds: 700));
        await _playAITurn();
      }
    }
  }

  CardModel _chooseAICard(String player) {
    final legal = _legalCards(player);
    if (legal.isEmpty) return _handFor(player).first;
    if (currentTrick.isEmpty) {
      return _pickLeadCard(player);
    }

    final leadSuit = currentTrick.first.card.suit;
    final winner = _currentWinningCard();
    final partnerWinning = _isPartnerWinning(player);
    final followCards = legal.where((card) => card.suit == leadSuit).toList();
    if (followCards.isNotEmpty) {
      if (partnerWinning) return _lowestPointCard(followCards);
      final canBeat = followCards
          .where((card) => _trickCardStrength(card, leadSuit) >
              _trickCardStrength(winner.card, leadSuit))
          .toList();
      if (canBeat.isNotEmpty) return _minimalWinningCard(canBeat, leadSuit);
      return _lowestPointCard(followCards);
    }

    final trumps = legal.where(_isTrump).toList();
    if (trumps.isNotEmpty) {
      if (partnerWinning) return _lowestPointCard(legal);
      final canBeat = trumps
          .where((card) => _trickCardStrength(card, leadSuit) >
              _trickCardStrength(winner.card, leadSuit))
          .toList();
      if (canBeat.isNotEmpty) return _minimalWinningCard(canBeat, leadSuit);
      return _lowestPointCard(trumps);
    }

    return _lowestPointCard(legal);
  }

  Future<void> _playAITurn() async {
    if (!gameStarted || gameOver) {
      print("⛔ IA ne joue pas : gameStarted=$gameStarted, gameOver=$gameOver");
      return;
    }
    final current = callSystem.currentPlayer;
    print("🤖 Tour IA : $current");
    if (current == "Sud") {
      print("⛔ C'est le tour de Sud, l'IA s'arrête.");
      return;
    }
    if (_handFor(current).isEmpty) {
      print("⛔ $current n'a plus de cartes.");
      return;
    }
    final card = _chooseAICard(current);
    await _playCard(current, card);
  }

  bool _canPlayCard(CardModel card) {
    if (callSystem.currentPlayer != "Sud") return false;
    if (!playerHand.contains(card)) return false;
    return _legalCards("Sud").contains(card);
  }

  Widget _buildPlayerHand(List<CardModel> cards, {required String playerName}) {
    final legal = playerName == "Sud" ? _legalCards("Sud") : [];
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty
        ? 0.0
        : cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  right: (cards.length - 1 - i) * overlap,
                  child: GestureDetector(
                    onTap: playerName == "Sud" && _canPlayCard(cards[i])
                        ? () => _playCard("Sud", cards[i])
                        : null,
                    child: SvgPicture.asset(
                      cards[i].assetPath,
                      width: cardWidth,
                      height: cardHeight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  PlayedCard? _playedCardFor(String player) {
    for (final played in currentTrick) {
      if (played.player == player) return played;
    }
    return null;
  }

  Widget _showTrickArea() {
    final playedMap = {
      for (final player in ['Nord', 'Est', 'Sud', 'Ouest'])
        player: _playedCardFor(player),
    };

    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: const Alignment(0, -0.58),
            child: _buildTrickCard(playedMap['Nord']),
          ),
          // Est et Ouest rapprochés du centre
          Align(
            alignment: const Alignment(0.38, -0.05),
            child: _buildTrickCard(playedMap['Est']),
          ),
          Align(
            alignment: const Alignment(-0.38, -0.05),
            child: _buildTrickCard(playedMap['Ouest']),
          ),
          Align(
            alignment: const Alignment(0, 0.6),
            child: _buildTrickCard(playedMap['Sud']),
          ),
        ],
      ),
    );
  }

  Widget _buildTrickCard(PlayedCard? playedCard) {
    if (playedCard == null) {
      return Container(
        width: 50,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    return SvgPicture.asset(
      playedCard.card.assetPath,
      width: 42,
      height: 54,
    );
  }

  Future<void> _showCallBubble(String player, CallOption option) async {
    setState(() {
      showCallBubble = true;
      callBubblePlayer = player;
      callBubbleText = _callOptionLabel(option);
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      showCallBubble = false;
    });
  }

  Future<void> _dealRemainingCards() async {
    for (var player in order) {
      await Future.delayed(const Duration(milliseconds: 600), () {
        setState(() {
          _giveCards(player, 3);
        });
      });
    }
  }

  Future<void> _finishBidding() async {
    biddingFinished = true;
    print("Appels terminés, on commence la partie !");
    await _dealRemainingCards();
    final sorted = _sortedSouthHand(callSystem.contractCall);
    setState(() {
      playerHand = sorted;
      winningPlayer = callSystem.contractWinner;
    });

    _startGame();
    if (callSystem.currentPlayer != "Sud") {
      print("⏳ IA doit commencer la manche.");
      Future.delayed(Duration.zero, () => _playAITurn());
    } else {
      print("🎮 Sud commence la manche.");
    }
  }

  Future<void> _showCallPopup() async {
    final current = callSystem.currentPlayer;
    starterPlayer ??= current;

    if (current != "Sud") {
      // IA joue automatiquement en choisissant la couleur la plus présente
      final option = _bestCallForPlayer(current);
      await callSystem.makeCall(option);
      await _showCallBubble(current, option);

      if (!callSystem.isFinished()) {
        await _showCallPopup();
      } else {
        await _finishBidding();
      }
    } else {
      // Joueur humain → popup
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          availableCalls: callSystem.availableCalls,
          onCall: (option) async {
            await callSystem.makeCall(option);
            await _showCallBubble(current, option);
            if (!callSystem.isFinished()) {
              await _showCallPopup();
            } else {
              await _finishBidding();
            }
          },
        ),
      );
    }
  }

  Widget _buildOverlapCardsRightToLeft(
    List<CardModel> cards, {
    bool showBack = false,
  }) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty
        ? 0.0
        : cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  right: (cards.length - 1 - i) * overlap,
                  child: SvgPicture.asset(
                    showBack
                        ? "assets/images/card/dos.svg"
                        : cards[i].assetPath,
                    width: cardWidth,
                    height: cardHeight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlapCardsTopToBottom(List<CardModel> cards) {
    const cardWidth = 100.0;
    const cardHeight = 60.0;
    const overlap = 24.0;
    final height = cards.isEmpty
        ? 0.0
        : cardHeight + (cards.length - 1) * overlap;

    return SizedBox(
      width: cardWidth,
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  top: i * overlap,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: SvgPicture.asset(
                      "assets/images/card/dos.svg",
                      width: cardHeight,
                      height: cardWidth,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marker({required Color color}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _playerAvatar(String player) {
    final isCurrentPlayer = callSystem.currentPlayer == player;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrentPlayer ? Colors.yellow : Colors.transparent,
          width: 3,
        ),
      ),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[300],
        ),
        child: Center(
          child: Text(
            player[0],
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _positionedMarker(String player, Color color) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;
    switch (player) {
      case "Nord":
        return Positioned(
          top: 80,
          left: w * 0.5 - 28,
          child: _playerAvatar(player),
        );
      case "Est":
        return Positioned(
          right: 12,
          top: h * 0.35,
          child: _playerAvatar(player),
        );
      case "Ouest":
        return Positioned(
          left: 12,
          top: h * 0.35,
          child: _playerAvatar(player),
        );
      case "Sud":
      default:
        return Positioned(
          bottom: 12,
          left: w * 0.5 - 28,
          child: _playerAvatar(player),
        );
    }
  }

  Widget _positionedCallBubble() {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;

    Widget content = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        callBubbleText,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );

    switch (callBubblePlayer) {
      case "Nord":
        return Positioned(top: 12, left: w * 0.5 - 60, child: content);
      case "Est":
        return Positioned(right: 12, top: h * 0.4, child: content);
      case "Ouest":
        return Positioned(left: 12, top: h * 0.4, child: content);
      case "Sud":
      default:
        return Positioned(bottom: 160, left: w * 0.5 - 60, child: content);
    }
  }

  Widget _buildGameInfoBar() {
    final contractLabel = callSystem.contractCall != null
        ? _callOptionLabel(callSystem.contractCall!)
        : "En attente";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // Ici tu peux mettre une alerte de confirmation
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Confirmation", textAlign: TextAlign.center),
                  content: const Text("Voulez-vous abandonner ?", textAlign: TextAlign.center),
                  actionsAlignment: MainAxisAlignment.center,
                  actions: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Non", style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        Navigator.of(context).pop(); // ferme le dialogue
                        Navigator.pop(context); // quitte la page
                      },
                      child: const Text("Oui", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
          Column(
            children: [
              const Text(
                "Score",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                "${gameScore["NS"] ?? 0} - ${gameScore["EO"] ?? 0}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Column(
            children: [
              const Text(
                "Contrat",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                contractLabel,
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (callSystem.contractWinner != null)
                Text(
                  callSystem.contractWinner!,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
          Column(
            children: [
              const Text(
                "Pli",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                tricksPlayed.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Alignment _alignmentForPlayer(String player) {
    switch (player) {
      case "Nord":
        return const Alignment(0, -0.85);
      case "Est":
        return const Alignment(0.85, 0);
      case "Ouest":
        return const Alignment(-0.85, 0);
      case "Sud":
      default:
        return const Alignment(0, 0.85);
    }
  }

  Widget _buildDealAnimation() {
    return AnimatedAlign(
      alignment: dealCardAtTarget
          ? _alignmentForPlayer(animatingDealPlayer!)
          : Alignment.center,
      duration: dealAnimationDuration,
      curve: Curves.easeInOut,
      child: SvgPicture.asset(
        "assets/images/card/dos.svg",
        width: 60,
        height: 80,
      ),
    );
  }

  Widget _buildPlayAnimation() {
    return AnimatedAlign(
      alignment: playCardAtCenter
          ? Alignment.center
          : _alignmentForPlayer(animatingPlayPlayer!),
      duration: playAnimationDuration,
      curve: Curves.easeInOut,
      child: SvgPicture.asset(
        animatingPlayCard!.assetPath,
        width: 80,
        height: 100,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/background.png",
              fit: BoxFit.cover,
            ),
          ),
          if (animatingDealCard != null) _buildDealAnimation(),
          if (animatingPlayCard != null) _buildPlayAnimation(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  // Barre d'infos (Score, Contrat, Pli)
                  _buildGameInfoBar(),
                  
                  const SizedBox(height: 12),

                  // Nord (IA 0)
                  SizedBox(
                    height: 120,
                    child: _buildOverlapCardsRightToLeft(
                      aiHands[0],
                      showBack: true,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Centre avec Ouest et Est
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(aiHands[2]),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(aiHands[1]),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sud (joueur humain)
                  SizedBox(
                    height: 140,
                    child: _buildPlayerHand(playerHand, playerName: "Sud"),
                  ),
                ],
              ),
            ),
          ),

          // Afficher la zone de pli en overlay pour ne pas impacter le layout des mains
          Positioned(
            top: MediaQuery.of(context).size.height * 0.33,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: true,
              child: _showTrickArea(),
            ),
          ),

          if (showCallBubble) _positionedCallBubble(),
          
          // Afficher les avatars des joueurs avec contour pour le joueur actif
          _positionedMarker("Nord", Colors.black),
          _positionedMarker("Est", Colors.white),
          _positionedMarker("Ouest", Colors.white),
          _positionedMarker("Sud", Colors.black),

          // Overlay : résultat de la manche + bouton Suivant
          if (waitingForNextHand)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Card(
                    color: Colors.blueGrey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Résultat de la manche', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          if (handHistory.isNotEmpty && handHistory.last.dedans)
                            const Text('Dedans !', style: TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('NS : +${lastHandDelta["NS"] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          Text('EO : +${lastHandDelta["EO"] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: overallWinner == null ? _applyLastHandAndNext : null,
                            child: const Text('Suivant'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Overlay : victoire de la partie
          if (overallWinner != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    color: Colors.green[800],
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Victoire : ${overallWinner == 'NS' ? 'Nord-Sud' : 'Est-Ouest'}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await StatsService().recordGameResult(
                                gameName: 'belote',
                                won: overallWinner == 'NS',
                                context: context,
                              );
                              // reset complet pour recommencer une nouvelle partie
                              setState(() {
                                gameScore = {"NS": 0, "EO": 0};
                                overallWinner = null;
                                waitingForNextHand = false;
                                lastHandDelta = {"NS": 0, "EO": 0};
                                handHistory.clear();
                                teamPoints = {"NS": 0, "EO": 0};
                                tricksPlayed = 0;
                                currentTrick = [];
                                playerHand.clear();
                                aiHands = [[], [], []];
                                deck = Deck();
                                deck.shuffle();
                                // Nouveau départ de partie : choisir aléatoirement le premier joueur
                                starterIndex = Random().nextInt(players.length);
                                order = [for (int i = 0; i < players.length; i++) players[(starterIndex + i) % players.length]];
                                callSystem = CallSystem(players, initialIndex: starterIndex);
                                biddingFinished = false;
                                gameOver = false;
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _dealCards();
                              });
                            },
                            child: const Text('Recommencer'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _showStatistics,
                            child: const Text('Statistiques'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          if (!biddingFinished)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 40,
              left: MediaQuery.of(context).size.width / 2 - 30,
              child: SvgPicture.asset("assets/images/card/dos.svg", height: 60),
            ),
        ],
      ),
    );
  }
}
