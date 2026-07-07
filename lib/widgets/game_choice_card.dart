import 'package:flutter/material.dart';
import '../screens/belote_screen.dart';
import '../screens/ludo_screen.dart';

class GameChoiceCard extends StatefulWidget {
  final String title;
  final VoidCallback? onTap;
  final VoidCallback? onClosePopup;

  const GameChoiceCard({
    super.key,
    required this.title,
    this.onTap,
    this.onClosePopup,
  });

  @override
  State<GameChoiceCard> createState() => GameChoiceCardState();
}

class GameChoiceCardState extends State<GameChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void _onTap() {
    _controller.forward().then((_) {
      if (widget.onTap != null) {
        widget.onTap!();
        return;
      }

      Future? future;
      if (widget.title == 'Belote') {
        future = Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, _, _) => const BeloteScreen(),
            transitionsBuilder: (_, animation, _, child) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
          ),
        );
      } else if (widget.title == 'Ludo') {
        future = Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, _, _) => const LudoScreen(),
            transitionsBuilder: (_, animation, _, child) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
          ),
        );
      } else {
        future = showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Rami"),
            content: const Text("En cours de développement"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }

      future.then((_) {
        if (mounted) _controller.reverse();
      });
    });
  }

  void resetCard() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * 3.14; // rotation en radians
          final isFront = angle < 1.57; // avant si < 90°

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(angle),
            child: isFront ? _buildFrontFace() : _buildBackFace(),
          );
        },
      ),
    );
  }

  Widget _buildFrontFace() {
    return Container(
      width: 100,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage("assets/images/card.png"), // fond carte
          fit: BoxFit.cover,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 230, 207, 0),
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 4,
                  offset: Offset(1, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackFace() {
    return Container(
      width: 100,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(2, 4),
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          "assets/images/logo.png", // ton logo au centre
          height: 60,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
