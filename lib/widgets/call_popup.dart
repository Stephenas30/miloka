import 'package:flutter/material.dart';
import '../game/call_system.dart';

class CallPopup extends StatelessWidget {
  final String playerName;
  final Function(CallOption) onCall;

  const CallPopup({super.key, required this.playerName, required this.onCall});

  @override
  Widget build(BuildContext context) {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Appel de $playerName",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Affichage circulaire des options
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: options.map((opt) {
                return ElevatedButton(
                  onPressed: () {
                    onCall(opt);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                  ),
                  child: Text(opt.name),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Bouton Passer
            ElevatedButton(
              onPressed: () {
                onCall(CallOption.pass);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: const Text("Passer"),
            ),
          ],
        ),
      ),
    );
  }
}
