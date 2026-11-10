import 'dart:math';
import '../models/card_model.dart';
import 'call_system.dart';
import 'played_card.dart';
import 'belote_scoring.dart' as scoring;

class BeloteRules {
  static String teamOf(String player) => scoring.teamOf(player);

  static String callOptionLabel(CallOption option) => scoring.callOptionLabel(option);

  static int rankValue(Rank rank, CallOption mode) => scoring.rankValue(rank, mode);

  static bool isContractProposal(CallOption option) {
    return option == CallOption.treble ||
        option == CallOption.diamond ||
        option == CallOption.heart ||
        option == CallOption.spade ||
        option == CallOption.sansAs ||
        option == CallOption.toutAs;
  }

  static Suit? contractTrumpSuit(CallSystem callSystem) => scoring.contractTrumpSuit(callSystem);

  static bool isTrump(CardModel card, CallSystem callSystem) => scoring.isTrump(card, callSystem);

  static int trickCardStrength(CardModel card, Suit? leadSuit, CallSystem callSystem) =>
      scoring.trickCardStrength(card, leadSuit, callSystem);

  static int cardPointValue(CardModel card, CallSystem callSystem) =>
      scoring.cardPointValue(card, callSystem);

  static List<CardModel> sortSouthHand(List<CardModel> cards, CallOption? contractCall) {
    final sortedCards = List<CardModel>.from(cards);
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

    sortedCards.sort((a, b) {
      final aGroup = suitOrder.indexOf(a.suit);
      final bGroup = suitOrder.indexOf(b.suit);
      if (aGroup != bGroup) return aGroup.compareTo(bGroup);

      final aMode = calledSuit != null && a.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      final bMode = calledSuit != null && b.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      return rankValue(b.rank, bMode).compareTo(rankValue(a.rank, aMode));
    });

    return sortedCards;
  }

  static List<CardModel> legalCards(String player, List<CardModel> hand, List<PlayedCard> currentTrick, CallSystem callSystem) {
    if (currentTrick.isEmpty) return hand;
    final leadSuit = currentTrick.first.card.suit;

    final leadCards = hand.where((card) => card.suit == leadSuit).toList();
    if (leadCards.isNotEmpty) {
      final isToutAsContract = callSystem.contractCall == CallOption.toutAs;
      final isTrumpSuit = contractTrumpSuit(callSystem) == leadSuit && callSystem.contractCall != CallOption.sansAs;
      final shouldApplySurtrumpRule = isToutAsContract || isTrumpSuit;

      if (shouldApplySurtrumpRule) {
        final cardsOfLeadSuitOnTable = currentTrick
            .where((played) => played.card.suit == leadSuit)
            .map((played) => played.card)
            .toList();

        if (cardsOfLeadSuitOnTable.isNotEmpty) {
          final strongestOnTable = cardsOfLeadSuitOnTable
              .map((c) => trickCardStrength(c, leadSuit, callSystem))
              .reduce(max);

          final strongerCards = leadCards
              .where((card) => trickCardStrength(card, leadSuit, callSystem) > strongestOnTable)
              .toList();

          if (strongerCards.isNotEmpty) {
            return strongerCards;
          }
        }
      }

      return leadCards;
    }

    final isTrumpContract = callSystem.contractCall == CallOption.treble ||
        callSystem.contractCall == CallOption.diamond ||
        callSystem.contractCall == CallOption.heart ||
        callSystem.contractCall == CallOption.spade ||
        callSystem.contractCall == CallOption.toutAs;

    if (isTrumpContract) {
      if (callSystem.contractCall == CallOption.toutAs) {
        return hand;
      }
      final trumps = hand.where((card) => isTrump(card, callSystem)).toList();
      if (trumps.isEmpty) return hand;

      if (currentTrick.length == 2) {
        final leadCard = currentTrick[0].card;
        final leadPlayer = currentTrick[0].player;
        if (teamOf(leadPlayer) == teamOf(player)) {
          final secondCard = currentTrick[1].card;
          if (!isTrump(secondCard, callSystem) &&
              trickCardStrength(leadCard, leadSuit, callSystem) > trickCardStrength(secondCard, leadSuit, callSystem)) {
            return hand;
          }
        }
      }

      final trumpsOnTable = currentTrick
          .where((played) => isTrump(played.card, callSystem))
          .map((played) => played.card)
          .toList();

      if (trumpsOnTable.isNotEmpty) {
        final highestOnTable = trumpsOnTable
            .map((c) => rankValue(c.rank, CallOption.toutAs))
            .reduce(max);

        final higherTrumps = trumps
            .where((c) => rankValue(c.rank, CallOption.toutAs) > highestOnTable)
            .toList();

        if (higherTrumps.isNotEmpty) {
          return higherTrumps;
        }

        return trumps;
      }

      return trumps;
    }

    return hand;
  }

  static PlayedCard currentWinningCard(List<PlayedCard> currentTrick, CallSystem callSystem) {
    final leadSuit = currentTrick.first.card.suit;
    PlayedCard winner = currentTrick.first;
    for (final played in currentTrick.skip(1)) {
      if (trickCardStrength(played.card, leadSuit, callSystem) >
          trickCardStrength(winner.card, leadSuit, callSystem)) {
        winner = played;
      }
    }
    return winner;
  }

  static bool isPartnerWinning(String player, List<PlayedCard> currentTrick, CallSystem callSystem) {
    final winner = currentWinningCard(currentTrick, callSystem);
    return teamOf(winner.player) == teamOf(player) && winner.player != player;
  }

  static CardModel lowestPointCard(List<CardModel> candidates, List<PlayedCard> currentTrick, CallSystem callSystem) {
    candidates.sort((a, b) {
      final aPoint = cardPointValue(a, callSystem);
      final bPoint = cardPointValue(b, callSystem);
      if (aPoint != bPoint) return aPoint.compareTo(bPoint);
      return trickCardStrength(a, currentTrick.first.card.suit, callSystem)
          .compareTo(trickCardStrength(b, currentTrick.first.card.suit, callSystem));
    });
    return candidates.first;
  }

  static CardModel minimalWinningCard(List<CardModel> candidates, Suit leadSuit, CallSystem callSystem) {
    candidates.sort((a, b) {
      final aStrength = trickCardStrength(a, leadSuit, callSystem);
      final bStrength = trickCardStrength(b, leadSuit, callSystem);
      if (aStrength != bStrength) return aStrength.compareTo(bStrength);
      return cardPointValue(a, callSystem).compareTo(cardPointValue(b, callSystem));
    });
    return candidates.first;
  }

  static CardModel pickLeadCard(String player, List<CardModel> hand, CallSystem callSystem) {
    hand.sort((a, b) {
      final aStrength = trickCardStrength(a, null, callSystem);
      final bStrength = trickCardStrength(b, null, callSystem);
      if (aStrength != bStrength) return bStrength.compareTo(aStrength);
      return cardPointValue(b, callSystem).compareTo(cardPointValue(a, callSystem));
    });
    return hand.first;
  }

  static Map<String, int> computeHandScores(CallSystem callSystem, Map<String, int> teamPoints) =>
      scoring.computeHandScores(callSystem, teamPoints);
}
