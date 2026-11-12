import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service/supabase_service.dart';
import '../service/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  User? _currentUser;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;

  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      _currentUser = _supabaseService.getCurrentUser();
      if (_currentUser != null) {
        await _loadUserProfile();
      }
    } catch (_) {
      _currentUser = null;
      _userProfile = null;
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabaseService.signInWithGoogle();
      _currentUser = response.user;
      if (_currentUser != null) {
        await _loadUserProfile();
      }
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.login(email, password);
      _currentUser = await AuthService.getCurrentUser();
      if (_currentUser != null) {
        await _loadUserProfile();
      }
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(
    String email,
    String password,
    String? fullName,
    String username,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.register(email, password, fullName, username);
      _currentUser = await AuthService.getCurrentUser();
      if (_currentUser != null) {
        await _loadUserProfile();
      }
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserProfile() async {
    if (_currentUser == null) {
      _userProfile = null;
      return;
    }

    try {
      _userProfile = await _supabaseService.getUserProfile(_currentUser!.id);
    } catch (e) {
      _error = 'Erreur lors du chargement du profil: $e';
    } finally {
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await AuthService.signOut();
      _currentUser = null;
      _userProfile = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> data, {String? localAvatarPath}) async {
    if (_currentUser == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      String? avatarUrl = data['avatar_url']?.toString();
      if (localAvatarPath != null && localAvatarPath.isNotEmpty) {
        avatarUrl = await _supabaseService.uploadAvatar(localAvatarPath, _currentUser!.id) ?? localAvatarPath;
      }

      final payload = {
        ...data,
        'avatar_url': avatarUrl ?? data['avatar_url'] ?? '',
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabaseService.client.from('users').update(payload).eq(
        'id',
        _currentUser!.id,
      );
      await _loadUserProfile();
    } catch (e) {
      _error = 'Erreur lors de la mise à jour du profil: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    await _loadUserProfile();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
