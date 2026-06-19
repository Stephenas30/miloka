import 'package:flutter/material.dart';
import '../widgets/game_choice.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Logo en haut
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Image.asset("assets/images/logo.png", height: 200),
              ),
            ),

            // Les cartes au centre
            Expanded(
              child: Padding(padding: EdgeInsets.all(8), child: GameChoices()),
            ),

            // Signature en bas
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "by SDS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
