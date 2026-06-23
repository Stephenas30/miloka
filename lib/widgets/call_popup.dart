import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../game/call_system.dart';

class CallPopup extends StatelessWidget {
  final String playerName;
  final Function(CallOption) onCall;

  const CallPopup({super.key, required this.playerName, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double radius = 120; // distance du centre
    final options = [
      CallOption.treble,
      CallOption.diamond,
      CallOption.heart,
      CallOption.spade,
      CallOption.sansAs,
      CallOption.toutAs,
      CallOption.x2,
      CallOption.x4,
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: size.width * 0.8,
        height: size.height * 0.6,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Boutons disposés en cercle
            for (int i = 0; i < options.length; i++)
              Positioned(
                left: (size.width * 0.4) +
                    radius * math.cos((2 * math.pi / options.length) * i) -
                    30,
                top: (size.height * 0.3) +
                    radius * math.sin((2 * math.pi / options.length) * i) -
                    30,
                child: ElevatedButton(
                  onPressed: () {
                    onCall(options[i]);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                  ),
                  child: Text(options[i].name),
                ),
              ),

            // Bouton "Passer" au centre
            ElevatedButton(
              onPressed: () {
                onCall(CallOption.pass);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(30),
                backgroundColor: Colors.red,
              ),
              child: const Text("Passer"),
            ),
          ],
        ),
      ),
    );
  }
}
