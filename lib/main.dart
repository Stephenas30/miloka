import 'package:flutter/material.dart';
import 'package:miloka/screens/splash_screen.dart';

void main() {
  runApp(const MilokaApp());
}

class MilokaApp extends StatelessWidget {
  const MilokaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Miloka",
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }
}
