import 'package:flutter/material.dart';
import 'package:miloka/screens/connexion_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _OnboardingScreenState();
  }
}

class _OnboardingScreenState extends State<OnboardingScreen> {

  Future<void> startLoading() async {

    await Future.delayed(const Duration(seconds: 5));

    if(mounted){
      Navigator.pushReplacement(context, 
        MaterialPageRoute(builder: (_) => ConnexionScreen())
      );
    }

  }

  @override
  void initState() {
    super.initState();
    startLoading();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height,
          maxHeight: MediaQuery.of(context).size.height,
        ),
        child: Stack( 
          children: [
            Positioned.fill(child: ClipRRect(
              child: Image.asset(
                'assets/images/poster.png',
              
                fit: BoxFit.contain,
              ),
            ),),
          ],
        ),
      ),
      ) 
      
    );
  }
}
