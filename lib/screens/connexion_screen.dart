import 'package:flutter/material.dart';
import 'package:miloka/providers/auth_provider.dart';
import 'package:miloka/screens/home_screen.dart';
import 'package:miloka/screens/login_screen.dart';
import 'package:miloka/screens/register_screen.dart';
import 'package:provider/provider.dart';

class ConnexionScreen extends StatefulWidget {
  const ConnexionScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _ConnexionScreenState();
  }
}

class _ConnexionScreenState extends State<ConnexionScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage("assets/images/bkg-con.png"),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Consumer<AuthProvider>(
            builder: (ctx, authProvider, _) {
              if (authProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: [0.0, 0.2, 1.0],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 30,
                          right: 30,
                          top: 120,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Continuer avec",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            /*
                            _socialButton(
                              icon: Icons.facebook_outlined,
                              label: 'Facebook',
                              color: const Color(0xFF1877F2),
                              onPressed: () {},
                            ),
                            const SizedBox(height: 10),
                            */
                            _socialButton(
                              icon: Icons.mail,
                              label: 'Gmail',
                              color: const Color(0xFFDB4437),
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () async {
                                      final navigator = Navigator.of(context);
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        await authProvider.signInWithGoogle();
                                        if (mounted) {
                                          navigator.pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const HomeScreen(),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Erreur de connexion: $e',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                            ),
                            const SizedBox(height: 30),

                            Row(
                              children: [
                                const Expanded(
                                  child: Divider(color: Colors.black38),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    "ou",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  child: Divider(color: Colors.black38),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LoginScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  "Connexion",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Vous n'avez pas de compte?",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RegisterScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    "Inscription",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 12,
          children: [
            Icon(icon, color: color, size: 22),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
