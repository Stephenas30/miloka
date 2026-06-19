import 'package:flutter/material.dart';
import 'game_choice_card.dart';

List<dynamic> games = ["Belote", "Ludo"];

class GameChoices extends StatelessWidget {
  const GameChoices({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: games.length < 3 ? games.length : 3,
      childAspectRatio: 2/3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        ...List.generate(games.length, (item) => GameChoiceCard(title: games[item]),)
      ],
    );

    /* Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        GameChoiceCard(title: "Belote", isBelote: true),
        SizedBox(width: 20),
        GameChoiceCard(title: "Ludo", isLudo: true),
        SizedBox(width: 20),
        GameChoiceCard(title: "Ludo"),
      ],
    ); */
  }
}
