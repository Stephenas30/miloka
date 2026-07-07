import 'package:flutter/material.dart';
import 'package:miloka/screens/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://txqxbwogkfvbfawgxpvi.supabase.co',
    anonKey: 'sb_publishable_VKKEjDEE8nxsf3OPxNFE_Q_IoDKKVoE',
  );
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
