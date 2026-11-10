import 'package:miloka/service/storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient supabase = Supabase.instance.client;

  static Future<User?> getCurrentUser() async {
    return supabase.auth.currentUser;
  }

  static Future<void> register(
    String email,
    String password,
    String? fullName,
    String username,
  ) async {
    final AuthResponse response = await supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('Inscription impossible : utilisateur introuvable.');
    }

    final profileData = {
      'id': user.id,
      'email': user.email,
      'full_name': fullName?.trim() ?? '',
      'username': username.trim(),
      'avatar_url': '',
      'coins': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supabase.from('users').upsert(profileData);
  }

  static Future<void> login(String email, String password) async {
    final response = await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final session = response.session;
    final user = response.user;

    if (session == null || user == null) {
      throw Exception('Connexion impossible : session introuvable.');
    }

    await TokenStorage.writeTokenStorage(session.accessToken);
    await UserStorage.writeUserStorage(user.email ?? '');
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
    await TokenStorage.allDeleteStorage();
  }

  static Future<bool> listenSessionChange() async {
    final tokenLocal = await TokenStorage.readTokenStorage();
    final currentToken = supabase.auth.currentSession?.accessToken;

    if (tokenLocal == null || currentToken == null) {
      return false;
    }

    return currentToken == tokenLocal;
  }
}
