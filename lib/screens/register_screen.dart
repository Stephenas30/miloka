import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:miloka/screens/login_screen.dart';
import 'package:miloka/service/auth_service.dart';

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
    if (_passwordController.text == _cpasswordController.text) {
    setState(() {
      loading = true;
    });
      try {
        await AuthService.register(_mailController.text, _passwordController.text);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Inscription réussie"), backgroundColor: Colors.green,));
    } catch (e) {
        print(e);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
        setState(() {
          loading = false;
        });
      }
    }else{
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vueillez saisir le même mot de passe.', style: TextStyle(color: Colors.white),), backgroundColor: Colors.red,));
    }
  } 

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    _usernameController.dispose();
    _mailController.dispose();
    _passwordController.dispose();
    _cpasswordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text("Inscription", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 3, 10, 17),
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          child: Center(
          child: Padding(
              padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Form(
                  key: _formKey,
                    child: /*  ConstrainedBox(
                      constraints: BoxConstraints(
                        //maxHeight: MediaQuery.of(context).size.height - 150,
                      ),
                      child:  */ Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          spacing: 10,
                    children: [
                      TextFormField(
                              controller: _usernameController,
                              onChanged: (e) => handleInput(),
                              decoration: const InputDecoration(
                                hintText: 'Entrer votre nom d\'utilisation',
                                label: Text('Nom d\'utilisation', /* style: AppTextStyles.subtitle */),
                                fillColor: const Color.fromARGB(255, 8, 25, 42),
                          ),
                              style: TextStyle(color: Colors.black),
                              validator: (String? value) {
                          if (value == null || value.isEmpty) {
                                  return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                              controller: _mailController,
                              onChanged: (e) => handleInput(),
                              decoration: const InputDecoration(
                                hintText: 'Entrer votre email',
                                label: Text('E-mail', /* style: AppTextStyles.subtitle */),
                                fillColor: const Color.fromARGB(255, 8, 25, 42),
                        ),
                              style: TextStyle(color: Colors.black),
                              validator: (String? value) {
                          if (value == null || value.isEmpty) {
                                  return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                              controller: _passwordController,
                              onChanged: (e) => handleInput(),
                              style: TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                                hintText: 'Entrer votre mot de passe',
                                label: Text('Mot de passe', /* style: AppTextStyles.subtitle */),
                                fillColor: const Color.fromARGB(255, 8, 25, 42),
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
                            ),
                          ),
                        ),
                              obscureText: !showPassword,
                              validator: (String? value) {
                          if (value == null || value.isEmpty) {
                                  return 'Please enter some password';
                          }
                          return null;
                        },
                      ),
                            TextFormField(
                              controller: _cpasswordController,
                              onChanged: (e) => handleInput(),
                              decoration: InputDecoration(
                                hintText: 'Entrer votre mot de passe',
                                label: Text('Confirmer votre mot de passe', /* style: AppTextStyles.subtitle */),
                                fillColor: const Color.fromARGB(255, 8, 25, 42),
                              ),
                              style: TextStyle(color: Colors.black),
                              obscureText: true,
                              validator: (String? value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter some password';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 20),
                            ElevatedButton(
                              style: ButtonStyle(
                            /* backgroundColor: MaterialStateProperty.all<Color>(
                              loading ? Colors.grey : AppColors.primary
                            ), */
                          ),
                              onPressed: disabled | loading
                                  ? null
                                  : () {
                                      // Validate will return true if the form is valid, or false if
                                      // the form is invalid.
                                      if (_formKey.currentState!.validate()) {
                                        // Process data.
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
                                            AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                  : const Text('Continuer'),
                      ),
                    ],
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                            Text('Vous avez déjà un compte?', /* style: AppTextStyles.subtitle */),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                          context,
                          MaterialPageRoute(
                                    builder: (_) => LoginScreen(),
                          ),
                        );
                      },
                              child: Text('Connexion'),
                    ),
                  ],
                ),
              ],
            ),
          ),
                  // ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
