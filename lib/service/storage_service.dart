import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {

 static final storage = FlutterSecureStorage();

static void writeTokenStorage(String token) async{
  await storage.write(key: 'token', value: token);
}

static Future<String?> readTokenStorage() async {
  String? token = await storage.read(key: 'token');
  return token;
}

static void deleteTokenStorage() async {
  await storage.delete(key: 'token');
}

static void allDeleteStorage() async {
  await storage.deleteAll();
}

Future<bool> existingStorage(String key) async{
  bool containsKey = await storage.containsKey(key: 'token');
  return containsKey;
}

}

