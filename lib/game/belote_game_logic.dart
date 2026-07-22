import 'dart:math';
import '../game/call_system.dart';
import '../game/deck.dart';
import '../models/card_model.dart';
import 'belote_rules.dart';
import 'played_card.dart';

class BeloteGameLogic {
  final List<String> players;
  late Deck deck;
  late CallSystem callSystem;

  List<CardModel> playerHand = [];
  List<List<CardModel>> aiHands = [[], [], []];
  bool biddingFinished = false;
  bool gameStarted = false;
  bool gameOver = false;
  String? starterPlayer;
  String? winningPlayer;
  int tricksPlayed = 0;
  List<PlayedCard> currentTrick = [];
  Map<String, int> teamPoints = {'NS': 0, 'EO': 0};
  Map<String, int> gameScore = {'NS': 0, 'EO': 0};
  bool waitingForNextHand = false;
  Map<String, int> lastHandDelta = {'NS': 0, 'EO': 0};
  int starterIndex = 0;
  late List<String> order;

  BeloteGameLogic({required this.players}) {
    resetGame();
  }

  void resetGame() {
    deck = Deck();
    deck.shuffle();
    starterIndex = Random().nextInt(players.length);
    order = [for (int i = 0; i < players.length; i++) players[(starterIndex + i) % players.length]];
    callSystem = CallSystem(players, initialIndex: starterIndex);

    playerHand = [];
    aiHands = [[], [], []];
    biddingFinished = false;
    gameStarted = false;
    gameOver = false;
    starterPlayer = null;
    winningPlayer = null;
    tricksPlayed = 0;
    currentTrick = [];
    teamPoints = {'NS': 0, 'EO': 0};
    gameScore = {'NS': 0, 'EO': 0};
    waitingForNextHand = false;
    lastHandDelta = {'NS': 0, 'EO': 0};
  }

  List<CardModel> handFor(String player) {
    switch (player) {
      case 'Nord':
        return aiHands[0];
      case 'Est':
        return aiHands[1];
      case 'Ouest':
        return aiHands[2];
      default:
        return playerHand;
    }
  }

  void giveCards(String player, int count) {
    if (player == 'Nord') {
      aiHands[0].addAll(deck.deal(count));
    } else if (player == 'Est') {
      aiHands[1].addAll(deck.deal(count));
    } else if (player == 'Ouest') {
      aiHands[2].addAll(deck.deal(count));
    } else if (player == 'Sud') {
      playerHand.addAll(deck.deal(count));
    }
  }

  CallOption bestCallForPlayer(String player) {
    final hand = handFor(player);
    final counts = <Suit, int>{
      Suit.trefle: 0,
      Suit.carreau: 0,
      Suit.coeur: 0,
      Suit.pique: 0,
    };

    for (final card in hand) {
      counts[card.suit] = counts[card.suit]! + 1;
    }

    final sortedSuits = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedSuits) {
      final option = suitToCallOption(entry.key);
      if (callSystem.availableCalls.contains(option)) {
        return option;
      }
    }

    return CallOption.pass;
  }

  CallOption suitToCallOption(Suit suit) {
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

  List<CardModel> sortedSouthHand(CallOption? contractCall) {
    return BeloteRules.sortSouthHand(playerHand, contractCall);
  }

  List<CardModel> legalCards(String player) {
    return BeloteRules.legalCards(player, handFor(player), currentTrick, callSystem);
  }

  PlayedCard currentWinningCard() {
    return BeloteRules.currentWinningCard(currentTrick, callSystem);
  }

  bool isPartnerWinning(String player) {
    return BeloteRules.isPartnerWinning(player, currentTrick, callSystem);
  }

  CardModel lowestPointCard(List<CardModel> candidates) {
    return BeloteRules.lowestPointCard(candidates, currentTrick, callSystem);
  }

  CardModel minimalWinningCard(List<CardModel> candidates, Suit leadSuit) {
    return BeloteRules.minimalWinningCard(candidates, leadSuit, callSystem);
  }

  CardModel pickLeadCard(String player) {
    return BeloteRules.pickLeadCard(player, handFor(player), callSystem);
  }

  Map<String, int> computeHandScores() {
    return BeloteRules.computeHandScores(callSystem, teamPoints);
  }

  String nextPlayer(String current) {
    final index = players.indexOf(current);
    return players[(index + 1) % players.length];
  }

  bool canPlayCard(CardModel card, {String player = 'Sud'}) {
    if (callSystem.currentPlayer != player) return false;
    final hand = handFor(player);
    if (!hand.contains(card)) return false;
    return legalCards(player).contains(card);
  }

  String handWinningTeam() {
    final preneur = callSystem.contractWinner;
    if (preneur == null) return 'NS';
    final preneurTeam = BeloteRules.teamOf(preneur);
    final defenseTeam = preneurTeam == 'NS' ? 'EO' : 'NS';
    final preneurPoints = teamPoints[preneurTeam] ?? 0;
    final defensePoints = teamPoints[defenseTeam] ?? 0;

    if (preneurPoints > defensePoints) {
      return preneurTeam;
    }
    return defenseTeam;
  }

  void resolveTrick() {
    final leadSuit = currentTrick.first.card.suit;
    PlayedCard winner = currentTrick.first;
    for (final played in currentTrick) {
      final currentStrength = BeloteRules.trickCardStrength(played.card, leadSuit, callSystem);
      final winnerStrength = BeloteRules.trickCardStrength(winner.card, leadSuit, callSystem);
      if (currentStrength > winnerStrength) {
        winner = played;
      }
    }
    final trickPoints = currentTrick.fold(0, (sum, played) => sum + BeloteRules.cardPointValue(played.card, callSystem));
    final team = BeloteRules.teamOf(winner.player);
    teamPoints[team] = teamPoints[team]! + trickPoints;
    tricksPlayed += 1;
    final nextLeader = winner.player;
    currentTrick = [];
    callSystem.setCurrentPlayer(nextLeader);
  }
}
