import 'package:flutter/material.dart';
import 'package:miloka/screens/home_screen.dart';
import 'package:miloka/screens/login_screen.dart';
import 'package:miloka/screens/onbording_screen.dart';
import 'package:miloka/service/auth_service.dart';
import 'package:miloka/service/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen> {
  void loadApp() async {
    final token = await AuthService.listenSessionChange();

    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => token ? HomeScreen() : OnbordingScreen()),
      );
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    loadApp();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover
            ),
        ),
        child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image(image: AssetImage("assets/images/logo.png")),
            CircularProgressIndicator(),
          ],
        ),
      ),
      ) 
    );
  }
}
