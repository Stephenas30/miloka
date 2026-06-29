import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../game/call_system.dart';

class CallPopup extends StatelessWidget {
  final String playerName;
  final Function(CallOption) onCall;
  final List<CallOption> availableCalls;

  const CallPopup({
    super.key,
    required this.playerName,
    required this.onCall,
    required this.availableCalls,
  });

  String _callOptionLabel(CallOption option) {
    switch (option) {
      case CallOption.treble:
        return "Trèfle";
      case CallOption.diamond:
        return "Carreau";
      case CallOption.heart:
        return "Cœur";
      case CallOption.spade:
        return "Pique";
      case CallOption.sansAs:
        return "Sans As";
      case CallOption.toutAs:
        return "Tout As";
      case CallOption.x2:
        return "x2";
      case CallOption.x4:
        return "x4";
      case CallOption.pass:
        return "Passer";
    }
  }

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
                  onPressed: availableCalls.contains(options[i])
                      ? () {
                          onCall(options[i]);
                          Navigator.pop(context);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: availableCalls.contains(options[i])
                        ? null
                        : Colors.grey[400],
                    foregroundColor: availableCalls.contains(options[i])
                        ? null
                        : Colors.grey[600],
                  ),
                  child: Text(_callOptionLabel(options[i])),
                ),
              ),

            // Bouton "Passer" au centre
            ElevatedButton(
              onPressed: availableCalls.contains(CallOption.pass)
                  ? () {
                      onCall(CallOption.pass);
                      Navigator.pop(context);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(30),
                backgroundColor: availableCalls.contains(CallOption.pass)
                    ? null
                    : Colors.grey[400],
                foregroundColor: availableCalls.contains(CallOption.pass)
                    ? null
                    : Colors.grey[600],
              ),
              child: const Text("Passer"),
            ),
          ],
        ),
      ),
    );
  }
}
