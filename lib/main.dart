import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'service/supabase_service.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Masquer barre de statut et barre de navigation
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialiser Supabase
  await SupabaseService().initialize();

  runApp(const MilokaApp());
}

class MilokaApp extends StatelessWidget {
  const MilokaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Miloka",
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const SplashScreen(),
      ),
    );
  }
}
