import 'package:flutter/material.dart';
import 'package:miloka/screens/connexion_screen.dart';

class OnbordingScreen extends StatefulWidget {
  const OnbordingScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _OnbordingScreenState();
  }
}

class _OnbordingScreenState extends State<OnbordingScreen> {

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
    // TODO: implement initState
    startLoading();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
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
            

            /* Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Bienvenue dans Miloka",
                    /* style: AppTextStyles(context: context).titleAppBAr, */
                  ),
                  Text(
                    "Tous vos jeux préférés dans une seule application.",
                    /* style: AppTextStyles.subtitleCard, */
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 50,)
                ],
              ),
            ), */
          ],
        ),
      ),
      ) 
      
    );
  }
}
