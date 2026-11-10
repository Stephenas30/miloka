import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:miloka/screens/login_screen.dart';
import 'package:miloka/providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _RegisterScreenState();
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fnameController = TextEditingController();
  final TextEditingController _lnameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _mailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cpasswordController = TextEditingController();

  bool showPassword = false;
  bool loading = false;
  bool disabled = true;

  void handleInput() {
    if ((_usernameController.text.isNotEmpty) &&
        (_mailController.text.isNotEmpty) &&
        (_passwordController.text.isNotEmpty) &&
        (_cpasswordController.text.isNotEmpty)) {
      setState(() {
        disabled = false;
      });
    } else {
      setState(() {
        disabled = true;
      });
    }
  }

  void registerHandler() async {
    if (_passwordController.text != _cpasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez saisir le même mot de passe.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Le mot de passe doit contenir au moins 6 caractères'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final authProvider = context.read<AuthProvider>();
    try {
      await authProvider.register(
        _mailController.text,
        _passwordController.text,
        '${_fnameController.text} ${_lnameController.text}',
        _usernameController.text,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Inscription réussie"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
    _fnameController.dispose();
    _lnameController.dispose();
    _usernameController.dispose();
    _mailController.dispose();
    _passwordController.dispose();
    _cpasswordController.dispose();
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
                                        "Inscription",
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        TextFormField(
                                          controller: _lnameController,
                                          onChanged: (e) => handleInput(),
                                          decoration: const InputDecoration(
                                            hintText: 'Entrer votre nom',
                                            hintStyle: TextStyle(
                                              color: Colors.white60,
                                            ),
                                            label: Text(
                                              'Nom',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            fillColor: Colors.white24,
                                            filled: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          style: TextStyle(color: Colors.white),
                                          validator: (String? value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'Veuillez entrer votre nom';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        Column(
                                          spacing: 10,
                                          children: [
                                            TextFormField(
                                              controller: _fnameController,
                                              onChanged: (e) => handleInput(),
                                              decoration: const InputDecoration(
                                                hintText: 'Entrer votre prénom',
                                                hintStyle: TextStyle(
                                                  color: Colors.white60,
                                                ),
                                                label: Text(
                                                  'Prénom',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                fillColor: Colors.white24,
                                                filled: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                              validator: (String? value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return 'Veuillez entrer votre prénom';
                                                }
                                                return null;
                                              },
                                            ),
                                            TextFormField(
                                              controller: _usernameController,
                                              onChanged: (e) => handleInput(),
                                              decoration: const InputDecoration(
                                                hintText:
                                                    'Entrer votre nom d\'utilisation',
                                                hintStyle: TextStyle(
                                                  color: Colors.white60,
                                                ),
                                                label: Text(
                                                  'Nom d\'utilisation',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                fillColor: Colors.white24,
                                                filled: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                              validator: (String? value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return 'Veuillez entrer un nom d\'utilisateur';
                                                }
                                                return null;
                                              },
                                            ),
                                            TextFormField(
                                              controller: _mailController,
                                              onChanged: (e) => handleInput(),
                                              decoration: const InputDecoration(
                                                hintText: 'Entrer votre email',
                                                hintStyle: TextStyle(
                                                  color: Colors.white60,
                                                ),
                                                label: Text(
                                                  'E-mail',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                fillColor: Colors.white24,
                                                filled: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
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
                                              controller: _passwordController,
                                              onChanged: (e) => handleInput(),
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                              decoration: InputDecoration(
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
                                                fillColor: Colors.white24,
                                                filled: true,
                                                border: OutlineInputBorder(),
                                                suffixIcon: IconButton(
                                                  onPressed: () {
                                                    setState(() {
                                                      showPassword =
                                                          !showPassword;
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
                                                  return 'Veuillez entrer un mot de passe';
                                                }
                                                if (value.length < 6) {
                                                  return 'Minimum 6 caractères';
                                                }
                                                return null;
                                              },
                                            ),
                                            TextFormField(
                                              controller: _cpasswordController,
                                              onChanged: (e) => handleInput(),
                                              decoration: const InputDecoration(
                                                hintText:
                                                    'Entrer votre mot de passe',
                                                hintStyle: TextStyle(
                                                  color: Colors.white60,
                                                ),
                                                label: Text(
                                                  'Confirmer votre mot de passe',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                fillColor: Colors.white24,
                                                filled: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                              obscureText: true,
                                              validator: (String? value) {
                                                if (value == null ||
                                                    value.isEmpty) {
                                                  return 'Veuillez confirmer le mot de passe';
                                                }
                                                if (value != _passwordController.text) {
                                                  return 'Les mots de passe ne correspondent pas';
                                                }
                                                return null;
                                              },
                                            ),
                                            const SizedBox(height: 20),
                                            ElevatedButton(
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
                                              onPressed: disabled | loading
                                                  ? null
                                                  : () {
                                                      if (_formKey.currentState!
                                                          .validate()) {
                                                        registerHandler();
                                                      }
                                                    },
                                              child: loading
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2.0,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(Colors.white),
                                                      ),
                                                    )
                                                  : const Text('Continuer'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Vous avez déjà un compte?',
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
                                                        LoginScreen(),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                'Connexion',
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
