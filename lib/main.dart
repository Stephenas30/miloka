import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/splash_screen.dart';
import 'service/supabase_service.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Masquer barre de statut et barre de navigation
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialiser Supabase
  await SupabaseService().initialize();

  // Bloquer la mise en veille tant que l'app est ouverte
  await WakelockPlus.enable();

  runApp(const MilokaApp());
}

class MilokaApp extends StatefulWidget {
  const MilokaApp({super.key});

  @override
  State<MilokaApp> createState() => _MilokaAppState();
}

class _MilokaAppState extends State<MilokaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Miloka",
        theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: GoogleFonts.playfairDisplayTextTheme(),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
