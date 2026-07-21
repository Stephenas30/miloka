import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  late SupabaseClient _client;
  late GoogleSignIn _googleSignIn;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://ttbhevnvmmizkiuwvvcf.supabase.co',
      publishableKey: 'sb_publishable_Bjf9EbegNic7EV4gY6Efpg_WEOZiRoh',
    );

    _client = Supabase.instance.client;

    _googleSignIn = GoogleSignIn.instance;
    await _googleSignIn.initialize(
      serverClientId:
          '523098863689-htmlr2jk0obqgcvp6tvekklnlv70fo4f.apps.googleusercontent.com',
    );
  }

  SupabaseClient get client => _client;
  GoogleSignIn get googleSignIn => _googleSignIn;

  // Authentification Google
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('ID token Google introuvable');
      }

      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      // Créer ou mettre à jour le profil utilisateur
      await _createOrUpdateUserProfile(response.user!);

      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Créer ou mettre à jour le profil utilisateur
  Future<void> _createOrUpdateUserProfile(User user) async {
    try {
      final googleUser = await _googleSignIn.attemptLightweightAuthentication();
      final existingProfile = await getUserProfile(user.id);

      final profileData = {
        'id': user.id,
        'email': user.email,
        'full_name':
            googleUser?.displayName ??
            user.userMetadata?['name'] ??
            existingProfile?['full_name'] ??
            '',
        'username':
            existingProfile?['username'] ??
            (googleUser?.displayName ?? user.userMetadata?['name'] ?? '')
                .toString()
                .replaceAll(' ', '')
                .toLowerCase(),
        'avatar_url':
            existingProfile?['avatar_url'] ??
            googleUser?.photoUrl ??
            user.userMetadata?['picture'] ??
            '',
        'coins': existingProfile?['coins'] ?? 0,
        /* 'is_connected': existingProfile?['is_connected'] ?? false, */
        'created_at':
            existingProfile?['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _client.from('users').upsert(profileData);
    } catch (e) {
      print('Erreur lors de la création du profil: $e');
    }
  }

  Future<String?> uploadAvatar(String localPath, String userId) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return null;
      }

      final extension = localPath.split('.').last.toLowerCase();
      final contentType = extension == 'png'
          ? 'image/png'
          : extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'application/octet-stream';
      final fileName = '$userId/avatar.$extension';
      final bytes = await file.readAsBytes();

      await _client.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );

      return _client.storage.from('avatars').getPublicUrl(fileName);
    } catch (e) {
      print('Erreur upload avatar: $e');
      return null;
    }
  }

  // Déconnexion
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _client.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Récupérer l'utilisateur actuel
  User? getCurrentUser() {
    return _client.auth.currentUser;
  }

  // Obtenir le profil utilisateur
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  // Vérifier si l'utilisateur est connecté
  bool isLoggedIn() {
    return _client.auth.currentUser != null;
  }

  // Stream des changements d'authentification
  Stream<AuthState> authStateChanges() {
    return _client.auth.onAuthStateChange;
  }

  Future<void> updateIsOnline() async {
    final user = getCurrentUser();
    final nowUtc = DateTime.now().toUtc();
    if (user != null) {
      await _client
          .from('users')
          .update({'is_connected': true, 'last_seen': nowUtc.toIso8601String()})
          .eq('id', user.id);
    }
  }

  Future<void> updateIsOffline() async {
    final user = getCurrentUser();
    final nowUtc = DateTime.now().toUtc();
    if (user != null) {
      await _client
          .from('users')
          .update({
            'is_connected': false,
            'last_seen': nowUtc.toIso8601String(),
          })
          .eq('id', user.id);

      await _client
          .from("amis")
          .update({'send_partie': 'none'})
          .or('id_ami.eq.${user.id},id_user.eq.${user.id}');
    }
  }
}
