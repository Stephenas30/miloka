import 'package:flutter/material.dart';
import 'package:miloka/screens/connexion_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _OnboardingScreenState();
  }
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _appVersion = '';

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
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${info.version}');
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
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Text(
                _appVersion,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      ) 
      
    );
  }
}

