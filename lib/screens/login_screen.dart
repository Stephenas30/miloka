import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:miloka/screens/home_screen.dart';
import 'package:miloka/screens/register_screen.dart';
import 'package:miloka/service/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _LoginScreenState();
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController userNameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool showPassword = false;
  bool loading = false;
  bool disabled = true;

  void handleInput(){
    if((userNameController.text.isNotEmpty) && (passwordController.text.isNotEmpty)){
      setState(() {
        disabled = false;
      });
    }else{
      setState(() {
        disabled = true;
      });
    }
  }

Future connexion() async {
    setState(() {
      loading = true;
    });
    try {
      await AuthService.login(userNameController.text, passwordController.text);

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));

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
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        loading = false;
      });
    }
  } 

  @override
  void dispose() {
    // TODO: implement dispose
    userNameController.dispose();
    passwordController.dispose();
    super.dispose();
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
        title: Text("Connexion", style: TextStyle(color: Colors.white),),
        backgroundColor: const Color.fromARGB(255, 3, 10, 17),
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 10,
                    children: <Widget>[
                      TextFormField(
                        controller: userNameController,
                        decoration: const InputDecoration(
                          fillColor: const Color.fromARGB(255, 8, 25, 42),
                          hintText: 'Entrer votre email',
                          label: Text('Email'),
                        ),
                        style: TextStyle(color: Colors.black),
                        onChanged: (e) => handleInput(),
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: passwordController,
                        onChanged: (e) => handleInput(),
                        style: TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          fillColor: const Color.fromARGB(255, 8, 25, 42),
                          hintText: 'Entrer votre mot de passe',
                          label: Text('Mot de passe'),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: ElevatedButton(
                          style: ButtonStyle(
                            /* backgroundColor: MaterialStateProperty.all<Color>(
                              loading ? Colors.grey : AppColors.primary
                            ), */
                          ),
                          onPressed: (disabled | loading) ? null : () {
                            // Validate will return true if the form is valid, or false if
                            // the form is invalid.
                            if (_formKey.currentState!.validate()) {
                              // Process data.
                              connexion();
                            }
                          },
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Continuer'),
                        ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text('Mot de passe oublié?'),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Vous n\'avez pas de compte?', /* style: AppTextStyles.subtitle */),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RegisterScreen(),
                                ),
                              ); 
                            },
                            child: Text('Inscription'),
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
      ),
    );
  }
}
