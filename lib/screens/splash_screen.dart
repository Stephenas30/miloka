import 'package:flutter/material.dart';
import 'package:miloka/screens/home_screen.dart';
import 'package:miloka/screens/onboarding_screen.dart';
import 'package:miloka/screens/update_required_screen.dart';
import 'package:miloka/service/auth_service.dart';
import 'package:miloka/service/version_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen> {
  String _appVersion = '';

  void loadApp() async {
    final token = await AuthService.listenSessionChange();

    Future.delayed(const Duration(seconds: 5), () async {
      if (!mounted) return;

      final upToDate = await VersionService.isUpToDate();
      if (!mounted) return;

      /* if (!upToDate) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const UpdateRequiredScreen(),
          ),
        );
        return;
      } */

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => token ? HomeScreen() : OnboardingScreen(),
        ),
      );
    });
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${info.version}');
  }

  @override
  void initState() {
    super.initState();
    loadApp();
    _loadVersion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image(image: AssetImage("assets/images/logo.png")),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
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
    );
  }
}
