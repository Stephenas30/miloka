import '../models/card_model.dart';
import 'call_system.dart' as cs;

String teamOf(String player) {
  return player == 'Nord' || player == 'Sud' ? 'NS' : 'EO';
}

String callOptionLabel(cs.CallOption option) {
  switch (option) {
    case cs.CallOption.treble: return 'Trèfle';
    case cs.CallOption.diamond: return 'Carreau';
    case cs.CallOption.heart: return 'Cœur';
    case cs.CallOption.spade: return 'Pique';
    case cs.CallOption.sansAs: return 'Sans As';
    case cs.CallOption.toutAs: return 'Tout As';
    case cs.CallOption.x2: return 'x2';
    case cs.CallOption.x4: return 'x4';
    case cs.CallOption.pass: return 'Passer';
  }
}

int rankValue(Rank rank, cs.CallOption mode) {
  switch (mode) {
    case cs.CallOption.sansAs:
      switch (rank) {
        case Rank.as: return 800;
        case Rank.dix: return 700;
        case Rank.roi: return 600;
        case Rank.dame: return 500;
        case Rank.valet: return 400;
        case Rank.neuf: return 300;
        case Rank.huit: return 200;
        case Rank.sept: return 100;
      }
    case cs.CallOption.toutAs:
    default:
      switch (rank) {
        case Rank.valet: return 800;
        case Rank.neuf: return 700;
        case Rank.as: return 600;
        case Rank.dix: return 500;
        case Rank.roi: return 400;
        case Rank.dame: return 300;
        case Rank.huit: return 200;
        case Rank.sept: return 100;
      }
  }
}

Suit? contractTrumpSuit(cs.CallSystem callSystem) {
  final contract = callSystem.contractCall;
  switch (contract) {
    case cs.CallOption.treble: return Suit.trefle;
    case cs.CallOption.diamond: return Suit.carreau;
    case cs.CallOption.heart: return Suit.coeur;
    case cs.CallOption.spade: return Suit.pique;
    default: return null;
  }
}

bool isTrump(CardModel card, cs.CallSystem callSystem) {
  if (callSystem.contractCall == cs.CallOption.toutAs) return true;
  if (callSystem.contractCall == cs.CallOption.sansAs) return false;
  final trumpSuit = contractTrumpSuit(callSystem);
  return card.suit == trumpSuit;
}

int trickCardStrength(CardModel card, Suit? leadSuit, cs.CallSystem callSystem) {
  if (leadSuit == null) {
    return rankValue(card.rank, cs.CallOption.toutAs);
  }
  final contract = callSystem.contractCall;
  final cardIsLead = card.suit == leadSuit;
  final trumpSuit = contractTrumpSuit(callSystem);
  final cardIsTrump = isTrump(card, callSystem);
  final leadIsTrump = leadSuit == trumpSuit;

  const int trumpBase = 2000;
  const int leadBase = 1000;

  if (contract == cs.CallOption.toutAs) {
    if (!cardIsLead) return 0;
    return leadBase + rankValue(card.rank, cs.CallOption.toutAs);
  }

  if (contract == cs.CallOption.sansAs) {
    if (!cardIsLead) return 0;
    return leadBase + rankValue(card.rank, cs.CallOption.sansAs);
  }

  if (leadIsTrump) {
    if (!cardIsTrump) return 0;
    return trumpBase + rankValue(card.rank, cs.CallOption.toutAs);
  }

  if (cardIsTrump) {
    return trumpBase + rankValue(card.rank, cs.CallOption.toutAs);
  }

  if (cardIsLead) {
    return leadBase + rankValue(card.rank, cs.CallOption.sansAs);
  }

  return 0;
}

int cardPointValue(CardModel card, cs.CallSystem callSystem) {
  final contract = callSystem.contractCall;
  final rank = card.rank;
  if (contract == cs.CallOption.sansAs) {
    switch (rank) {
      case Rank.as: return 11;
      case Rank.dix: return 10;
      case Rank.roi: return 4;
      case Rank.dame: return 3;
      case Rank.valet: return 2;
      case Rank.neuf:
      case Rank.huit:
      case Rank.sept: return 0;
    }
  }
  if (isTrump(card, callSystem)) {
    switch (rank) {
      case Rank.as: return 11;
      case Rank.dix: return 10;
      case Rank.roi: return 4;
      case Rank.dame: return 3;
      case Rank.valet: return 20;
      case Rank.neuf: return 14;
      case Rank.huit:
      case Rank.sept: return 0;
    }
  }
  switch (rank) {
    case Rank.as: return 11;
    case Rank.dix: return 10;
    case Rank.roi: return 4;
    case Rank.dame: return 3;
    case Rank.valet: return 2;
    case Rank.neuf:
    case Rank.huit:
    case Rank.sept: return 0;
  }
}

Map<String, int> computeHandScores(cs.CallSystem callSystem, Map<String, int> teamPoints) {
  final result = {'NS': 0, 'EO': 0};
  final contract = callSystem.contractCall;
  final preneur = callSystem.contractWinner;
  if (contract == null || preneur == null) return result;

  final preneurTeam = teamOf(preneur);
  final defenseTeam = preneurTeam == 'NS' ? 'EO' : 'NS';
  final preneurPoints = teamPoints[preneurTeam] ?? 0;
  final defensePoints = teamPoints[defenseTeam] ?? 0;
  final isX2 = callSystem.highestCall == cs.CallOption.x2;
  final isX4 = callSystem.highestCall == cs.CallOption.x4;
  final multiplier = isX4 ? 4 : isX2 ? 2 : 1;

  void award(String team, int pts) {
    result[team] = (result[team] ?? 0) + pts;
  }

  if (contract == cs.CallOption.sansAs) {
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

  if (contract == cs.CallOption.treble) {
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

  if (contract == cs.CallOption.diamond || contract == cs.CallOption.heart || contract == cs.CallOption.spade) {
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

  if (contract == cs.CallOption.toutAs) {
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
