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
      if (widget.title == 'Belote') {
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const BeloteScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
          ),
        );
      } else if (widget.title == 'Ludo') {
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const LudoScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return ScaleTransition(
                scale: animation,
                child: child,
              );
            },
          ),
        );
      } else {
        showDialog(
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
      width: 80,
      height: 40,
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
        child: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 20,
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
    );
  }

  Widget _buildBackFace() {
    return Container(
      width: 80,
      height: 40,
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
