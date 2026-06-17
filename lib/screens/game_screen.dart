import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math';
import '../game/deck.dart';
import '../models/card_model.dart';
import '../game/call_system.dart';
import '../widgets/call_popup.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Deck deck;
  late CallSystem callSystem;

  List<CardModel> playerHand = [];
  List<List<CardModel>> aiHands = [[], [], []]; // Nord, Est, Ouest

  late List<String> order; // ordre de distribution
  final List<String> players = ["Nord", "Est", "Sud", "Ouest"];

  @override
  void initState() {
    super.initState();
    deck = Deck();
    deck.shuffle();

    callSystem = CallSystem(players);

    // Choisir aléatoirement le joueur qui commence
    final startIndex = Random().nextInt(players.length);
    order = [
      for (int i = 0; i < players.length; i++)
        players[(startIndex + i) % players.length]
    ];

    // Lancer la distribution animée
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dealCards();
    });
  }

  /// Distribution animée : 3 cartes chacun puis 2 cartes chacun
  void _dealCards() async {
    // Premier tour : 3 cartes chacun
    for (var player in order) {
      await Future.delayed(const Duration(milliseconds: 800), () {
        setState(() {
          _giveCards(player, 3);
        });
      });
    }

    // Deuxième tour : 2 cartes chacun
    for (var player in order) {
      await Future.delayed(const Duration(milliseconds: 800), () {
        setState(() {
          _giveCards(player, 2);
        });
      });
    }

    // Quand la distribution est terminée → lancer le popup d’appel
    _showCallPopup();
  }

  void _giveCards(String player, int count) {
    if (player == "Nord") {
      aiHands[0].addAll(deck.deal(count));
    } else if (player == "Est") {
      aiHands[1].addAll(deck.deal(count));
    } else if (player == "Ouest") {
      aiHands[2].addAll(deck.deal(count));
    } else if (player == "Sud") {
      playerHand.addAll(deck.deal(count));
    }
  }

  void _showCallPopup() {
    final current = callSystem.currentPlayer;

    if (current != "Sud") {
      // IA joue automatiquement
      setState(() {
        final option = Random().nextBool() ? CallOption.pass : CallOption.treble;
        callSystem.makeCall(option);
      });
      if (!callSystem.isFinished()) {
        _showCallPopup();
      } else {
        print("Appels terminés, on commence la partie !");
      }
    } else {
      // Joueur humain → popup
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          onCall: (option) {
            setState(() {
              callSystem.makeCall(option);
            });
            if (!callSystem.isFinished()) {
              _showCallPopup();
            } else {
              print("Appels terminés, on commence la partie !");
            }
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Partie contre IA")),
      body: Stack(
        children: [
          Column(
            children: [
              // Nord (IA 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: aiHands[0].map((_) {
                  return SvgPicture.asset("assets/images/card/dos.svg", height: 80);
                }).toList(),
              ),

              const Spacer(),

              // Centre avec Ouest et Est
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Ouest (IA 2)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: aiHands[2].map((_) {
                      return SvgPicture.asset("assets/images/card/dos.svg", height: 80);
                    }).toList(),
                  ),

                  const Text("Table de jeu"),

                  // Est (IA 1)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: aiHands[1].map((_) {
                      return SvgPicture.asset("assets/images/card/dos.svg", height: 80);
                    }).toList(),
                  ),
                ],
              ),

              const Spacer(),

              // Sud (joueur humain)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: playerHand.map((card) {
                  return SvgPicture.asset(card.assetPath, height: 100);
                }).toList(),
              ),
            ],
          ),

          // Animation simple : carte qui glisse du centre
          // (exemple visuel, tu peux l’améliorer avec AnimatedPositioned)
          Positioned(
            top: MediaQuery.of(context).size.height / 2 - 40,
            left: MediaQuery.of(context).size.width / 2 - 30,
            child: SvgPicture.asset("assets/images/card/dos.svg", height: 60),
          ),
        ],
      ),
    );
  }
}
