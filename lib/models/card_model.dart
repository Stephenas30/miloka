enum Suit { carreau, coeur, pique, trefle }
enum Rank { sept, huit, neuf, dix, valet, dame, roi, as }

class CardModel {
  final Suit suit;
  final Rank rank;
  CardModel(this.suit, this.rank);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardModel && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => Object.hash(suit, rank);

  String get assetPath {
    // Exemple : assets/images/card/carreau-9.svg
    final suitName = suit.name; // carreau, coeur, pique, trefle
    final rankName = _rankToString(rank);
    return "assets/images/card/$suitName-$rankName.svg";
  }

  String _rankToString(Rank r) {
    switch (r) {
      case Rank.sept: return "7";
      case Rank.huit: return "8";
      case Rank.neuf: return "9";
      case Rank.dix: return "10";
      case Rank.valet: return "J";
      case Rank.dame: return "Q";
      case Rank.roi: return "K";
      case Rank.as: return "A";
    }
  }

  Map<String, dynamic> toMap() => {'suit': suit.name, 'rank': rank.name};

  factory CardModel.fromMap(Map<String, dynamic> map) => CardModel(
    Suit.values.byName(map['suit'] as String),
    Rank.values.byName(map['rank'] as String),
  );
}
