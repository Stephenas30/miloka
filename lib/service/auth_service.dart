import 'package:miloka/service/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final supabase = Supabase.instance.client;

  static Future<void> register(String email, String password, String? fullName, String username) async {
    final AuthResponse response = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    final user = response.user;

    final profileData = {
        'id': user?.id,
        'email': user?.email,
        'full_name': fullName,
        'username': username,
        'avatar_url': '',
        'coins': 0,
        /* 'is_connected': true, */
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

    await supabase.from('users').upsert(profileData);
    print('Utilisateur créé: ${response.user?.id}');
  }

  static Future<void> login(String email, String password) async {
    var response = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final session = response.session;
    final user = response.user;

    await TokenStorage.writeTokenStorage('${session?.accessToken}');
    await UserStorage.writeUserStorage('${user?.email}');

    print(session);
    print('Token: ${session?.accessToken}');
    print('User: ${user?.email}');
  }

  static Future<bool> listenSessionChange() async {
    final tokenLocal = await TokenStorage.readTokenStorage();
    if (tokenLocal == null) {
      print('Vérification: false (token local absent)');
      return false;
    }

    final currentToken = supabase.auth.currentSession?.accessToken;
    final verified = currentToken != null && currentToken == tokenLocal;

    print('Token local: $tokenLocal');
    print('Token courant: $currentToken');
    print('Vérification: $verified');

    return verified;
  }
}
