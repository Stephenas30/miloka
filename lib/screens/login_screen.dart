import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:miloka/screens/home_screen.dart';
import 'package:miloka/screens/register_screen.dart';
import 'package:miloka/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _LoginScreenState();
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool showPassword = false;
  bool disabled = true;
  bool _isLoading = false;

  void handleInput() {
    if ((userNameController.text.isNotEmpty) &&
        (passwordController.text.isNotEmpty)) {
      setState(() {
        disabled = false;
      });
    } else {
      setState(() {
        disabled = true;
      });
    }
  }

  Future<void> connexion() async {
    setState(() => _isLoading = true);
    final authProvider = context.read<AuthProvider>();
    try {
      await authProvider.loginWithEmail(
        userNameController.text,
        passwordController.text,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Connexion réussie",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    userNameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Stack(
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
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
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
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.arrow_back,
                                          color: Colors.white,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                      Text(
                                        "Connexion",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      spacing: 10,
                                      children: <Widget>[
                                        TextFormField(
                                          controller: userNameController,
                                          decoration: const InputDecoration(
                                            fillColor: Colors.white24,
                                            filled: true,
                                            hintText: 'Entrer votre email',
                                            hintStyle: TextStyle(
                                              color: Colors.white60,
                                            ),
                                            label: Text(
                                              'Email',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            border: OutlineInputBorder(),
                                          ),
                                          style: TextStyle(color: Colors.white),
                                          onChanged: (e) => handleInput(),
                                          validator: (String? value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'Veuillez entrer votre email';
                                            }
                                            if (!value.contains('@')) {
                                              return 'Email invalide';
                                            }
                                            return null;
                                          },
                                        ),
                                        TextFormField(
                                          controller: passwordController,
                                          onChanged: (e) => handleInput(),
                                          style: TextStyle(color: Colors.white),
                                          decoration: InputDecoration(
                                            fillColor: Colors.white24,
                                            filled: true,
                                            hintText:
                                                'Entrer votre mot de passe',
                                            hintStyle: TextStyle(
                                              color: Colors.white60,
                                            ),
                                            label: Text(
                                              'Mot de passe',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            border: OutlineInputBorder(),
                                            suffixIcon: IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  showPassword = !showPassword;
                                                });
                                              },
                                              icon: Icon(
                                                showPassword
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          obscureText: !showPassword,
                                          validator: (String? value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'Veuillez entrer votre mot de passe';
                                            }
                                            if (value.length < 6) {
                                              return 'Minimum 6 caractères';
                                            }
                                            return null;
                                          },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16.0,
                                          ),
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.black,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 40,
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: (disabled || _isLoading)
                                                ? null
                                                : () {
                                                    if (_formKey.currentState!
                                                        .validate()) {
                                                      connexion();
                                                    }
                                                  },
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : const Text('Continuer'),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final email = userNameController.text.trim();
                                            if (email.isEmpty || !email.contains('@')) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Veuillez d\'abord entrer votre email'),
                                                  backgroundColor: Colors.orange,
                                                ),
                                              );
                                              return;
                                            }
                                            try {
                                              await Supabase.instance.client.auth.resetPasswordForEmail(email);
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Email de réinitialisation envoyé à $email'),
                                                    backgroundColor: Colors.green,
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Erreur: $e'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          child: const Text(
                                            'Mot de passe oublié?',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              "Vous n'avez pas de compte?",
                                              style: TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        RegisterScreen(),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                'Inscription',
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
                                ],
                              ),
                            ),
                          ),
                        ],
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
