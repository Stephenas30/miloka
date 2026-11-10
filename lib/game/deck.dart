import 'dart:math';
import '../models/card_model.dart';

class Deck {
  final List<CardModel> cards = [];

  Deck() {
    for (var suit in Suit.values) {
      for (var rank in Rank.values) {
        cards.add(CardModel(suit, rank));
      }
    }
  }

  void shuffle() => cards.shuffle(Random());

  List<CardModel> deal(int count) {
    final hand = cards.take(count).toList();
    cards.removeRange(0, count);
    return hand;
  }
}
