import 'dart:math';
import '../game/call_system.dart';
import '../models/card_model.dart';
import 'played_card.dart';

class BeloteRules {
  static String teamOf(String player) {
    return player == 'Nord' || player == 'Sud' ? 'NS' : 'EO';
  }

  static String callOptionLabel(CallOption option) {
    switch (option) {
      case CallOption.treble:
        return 'Trèfle';
      case CallOption.diamond:
        return 'Carreau';
      case CallOption.heart:
        return 'Cœur';
      case CallOption.spade:
        return 'Pique';
      case CallOption.sansAs:
        return 'Sans As';
      case CallOption.toutAs:
        return 'Tout As';
      case CallOption.x2:
        return 'x2';
      case CallOption.x4:
        return 'x4';
      case CallOption.pass:
        return 'Passer';
    }
  }

  static int rankValue(Rank rank, CallOption mode) {
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

  static Suit? contractTrumpSuit(CallSystem callSystem) {
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

  static bool isTrump(CardModel card, CallSystem callSystem) {
    if (callSystem.contractCall == CallOption.toutAs) return true;
    if (callSystem.contractCall == CallOption.sansAs) return false;
    final trumpSuit = contractTrumpSuit(callSystem);
    return card.suit == trumpSuit;
  }

  static int trickCardStrength(CardModel card, Suit? leadSuit, CallSystem callSystem) {
    if (leadSuit == null) {
      return rankValue(card.rank, CallOption.toutAs);
    }
    final contract = callSystem.contractCall;
    final cardIsLead = card.suit == leadSuit;
    final trumpSuit = contractTrumpSuit(callSystem);
    final cardIsTrump = isTrump(card, callSystem);
    final leadIsTrump = leadSuit == trumpSuit;

    const int trumpBase = 2000;
    const int leadBase = 1000;

    if (contract == CallOption.toutAs) {
      if (!cardIsLead) return 0;
      return leadBase + rankValue(card.rank, CallOption.toutAs);
    }

    if (contract == CallOption.sansAs) {
      if (!cardIsLead) return 0;
      return leadBase + rankValue(card.rank, CallOption.sansAs);
    }

    if (leadIsTrump) {
      if (!cardIsTrump) return 0;
      return trumpBase + rankValue(card.rank, CallOption.toutAs);
    }

    if (cardIsTrump) {
      return trumpBase + rankValue(card.rank, CallOption.toutAs);
    }

    if (cardIsLead) {
      return leadBase + rankValue(card.rank, CallOption.sansAs);
    }

    return 0;
  }

  static int cardPointValue(CardModel card, CallSystem callSystem) {
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
    if (isTrump(card, callSystem)) {
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
      final trumps = hand.where((card) => isTrump(card, callSystem)).toList();
      if (trumps.isEmpty) return hand;

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

  static Map<String, int> computeHandScores(CallSystem callSystem, Map<String, int> teamPoints) {
    final result = {'NS': 0, 'EO': 0};
    final contract = callSystem.contractCall;
    final preneur = callSystem.contractWinner;
    if (contract == null || preneur == null) return result;

    final preneurTeam = teamOf(preneur);
    final defenseTeam = preneurTeam == 'NS' ? 'EO' : 'NS';
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
}
