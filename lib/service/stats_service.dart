import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatsService {
  static final StatsService _instance = StatsService._internal();
  factory StatsService() => _instance;
  StatsService._internal();

  Future<void> recordGameResult({
    required String gameName,
    required bool won,
    required BuildContext? context,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('player_games').insert({
        'user_id': user.id,
        'game_name': gameName,
        'won': won,
        'played_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('StatsService.recordGameResult error: $e');
    }
  }
}
