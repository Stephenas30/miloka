import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {

 static final storage = FlutterSecureStorage();

static Future<void> writeTokenStorage(String token) async{
  await storage.write(key: 'token', value: token);
}

static Future<String?> readTokenStorage() async {
  String? token = await storage.read(key: 'token');
  return token;
}

static void deleteTokenStorage() async {
  await storage.delete(key: 'token');
  UserStorage.deleteUserStorage();
}

static void allDeleteStorage() async {
  await storage.deleteAll();
}

Future<bool> existingStorage(String key) async{
  bool containsKey = await storage.containsKey(key: 'token');
  return containsKey;
}

}

class UserStorage {

 static final storage = FlutterSecureStorage();

static Future<void> writeUserStorage(String email) async{
  await storage.write(key: 'email', value: email);
}

static Future<String?> readUserStorage() async {
  String? email = await storage.read(key: 'email');
  return email;
}

static void deleteUserStorage() async {
  await storage.delete(key: 'email');
}

static void allDeleteStorage() async {
  await storage.deleteAll();
}

Future<bool> existingStorage(String key) async{
  bool containsKey = await storage.containsKey(key: 'email');
  return containsKey;
}

}

