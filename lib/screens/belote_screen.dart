import 'package:flutter/material.dart';
import '../widgets/game_choice_card.dart';
import '../widgets/game_mode_popup.dart';

class BeloteScreen extends StatefulWidget {
  const BeloteScreen({super.key});

  @override
  State<BeloteScreen> createState() => _BeloteScreenState();
}

class _BeloteScreenState extends State<BeloteScreen> {
  // Déclare les clés ici
  final GlobalKey<GameChoiceCardState> card1Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card2Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card3Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card4Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card5Key = GlobalKey<GameChoiceCardState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF006400),
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color.fromARGB(255, 255, 255, 255), Color.fromARGB(255, 255, 255, 255)],
              ).createShader(bounds),
              child: const Text(
                "Sélectionne ton défi",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GameChoiceCard(
                  key: card1Key,
                  title: "1 vs 1",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "1 vs 1",
                        onClosePopup: () {
                          card1Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card2Key,
                  title: "Classique",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Classique",
                        onClosePopup: () {
                          card2Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card3Key,
                  title: "Tournoi",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Tournoi",
                        onClosePopup: () {
                          card3Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GameChoiceCard(
                  key: card4Key,
                  title: "En ligne",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "En ligne",
                        onClosePopup: () {
                          card4Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card5Key,
                  title: "Contre IA",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Contre IA",
                        onClosePopup: () {
                          card5Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
