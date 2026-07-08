import 'package:flutter/material.dart';
import 'game_choice_card.dart';

List<dynamic> games = ["Belote", "Ludo"];

class GameChoices extends StatelessWidget {
  const GameChoices({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: games.length < 3 ? 250 : 150, // largeur max d'une carte
        childAspectRatio: 2 / 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) => GameChoiceCard(title: games[index]),
    );
  }
}