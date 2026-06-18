import 'package:flutter/material.dart';
import 'game_choice_card.dart';

class GameChoices extends StatelessWidget {
  const GameChoices({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        GameChoiceCard(title: "Belote", isBelote: true),
        SizedBox(width: 20),
        GameChoiceCard(title: "Ludo", isLudo: true),
        SizedBox(width: 20),
        GameChoiceCard(title: "Rami"),
      ],
    );
  }
}