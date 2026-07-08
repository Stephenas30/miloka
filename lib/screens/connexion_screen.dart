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
    // TODO: implement build
    return Scaffold(
      body: Center(
        child: Consumer<AuthProvider>(
          builder: (ctx, authProvider, _) {
            if (authProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(26),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/logo.png', width: 100),
                        SizedBox(height: 10),
                        Text("Continuer avec" /* style: AppTextStyles.title */),
                        SizedBox(height: 20),

                        OutlinedButton(
                          onPressed: () {},
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 20,
                            children: [
                              Icon(Icons.facebook_outlined),
                              Text('Facebook'),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: 
                            authProvider.isLoading
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
                                            builder: (_) => const HomeScreen(),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 20,
                            children: [Icon(Icons.mail), Text('Gmail')],
                          ),
                        ),
                        SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () {},
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 20,
                            children: [Icon(Icons.apple), Text('Apple')],
                          ),
                        ),
                        SizedBox(height: 20),
                        Text("ou" /* style: AppTextStyles.subtitle */),
                        SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => LoginScreen()),
                            );
                          },
                          child: Text("Connexion"),
                        ),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Vous n' avez pas de Compte?" /* style: AppTextStyles.subtitle */,
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
                              child: Text("Inscription"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
