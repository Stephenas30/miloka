import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageManager {
  static const String _tokenKey = 'token';
  static const String _emailKey = 'email';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<void> writeToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> readToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  static Future<void> writeUserEmail(String email) async {
    await _storage.write(key: _emailKey, value: email);
  }

  static Future<String?> readUserEmail() async {
    return _storage.read(key: _emailKey);
  }

  static Future<void> deleteUserEmail() async {
    await _storage.delete(key: _emailKey);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}

class TokenStorage {
  static Future<void> writeTokenStorage(String token) async {
    await SecureStorageManager.writeToken(token);
  }

  static Future<String?> readTokenStorage() async {
    return SecureStorageManager.readToken();
  }

  static Future<void> deleteTokenStorage() async {
    await SecureStorageManager.deleteToken();
    await UserStorage.deleteUserStorage();
  }

  static Future<void> allDeleteStorage() async {
    await SecureStorageManager.clearAll();
  }
}

class UserStorage {
  static Future<void> writeUserStorage(String email) async {
    await SecureStorageManager.writeUserEmail(email);
  }

  static Future<String?> readUserStorage() async {
    return SecureStorageManager.readUserEmail();
  }

  static Future<void> deleteUserStorage() async {
    await SecureStorageManager.deleteUserEmail();
  }

  static Future<void> allDeleteStorage() async {
    await SecureStorageManager.clearAll();
  }
}

