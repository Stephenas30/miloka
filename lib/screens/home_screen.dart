import 'package:flutter/material.dart';
import 'package:miloka/screens/profil_screen.dart';
import '../widgets/game_choice.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        onPressed: () {
          // Action when floating action button is pressed
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ProfilScreen()),
          );
        },
        child: Icon(Icons.settings),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
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
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: GameChoices(),
                    ),
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
            Positioned(
              top: 20,
              left: 10,
              child: Builder(
                builder: (buttonContext) {
                  return IconButton.filled(
                    onPressed: () {
                      final RenderBox box =
                          buttonContext.findRenderObject() as RenderBox;
                      final Offset position = box.localToGlobal(Offset.zero);
                      final Size size = box.size;

                      showMenu(
                        context: buttonContext,
                        items: const [
                          PopupMenuItem(
                            value: 'add_friend',
                            child: Text('Add Friend'),
                            
                          ),
                          PopupMenuItem(
                            value: 'view_friends',
                            child: Text('View Friends'),
                          ),
                        ],
                        position: RelativeRect.fromLTRB(
                          position.dx,
                          position.dy + size.height,
                          position.dx + size.width,
                          position.dy + size.height,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.people_alt_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    style: ButtonStyle(
                      backgroundColor: MaterialStatePropertyAll(
                        Colors.black.withOpacity(0.5),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
