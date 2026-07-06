import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/game_choice.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final coins = int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
            // Top controls (profil à gauche, boutique à droite)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
                        icon: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text('Jetons : $coins', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PurchaseScreen()),
                      );
                    },
                    icon: const Icon(Icons.storefront, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Logo en haut
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Image.asset("assets/images/logo.png", height: 200),
              ),
            ),

            // Les cartes au centre
            Expanded(
              child: Padding(padding: const EdgeInsets.all(8), child: GameChoices()),
            ),

            // Signature en bas
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "by SDS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
